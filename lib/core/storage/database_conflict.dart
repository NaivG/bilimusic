/// 数据库**落点扫描**：三处可能的位置上各有没有一份库 —— 只 `stat`，不开库、
/// 不建目录、不读偏好。
///
/// 背景：sqflite 的默认落点是
/// `absolute(join('.dart_tool','sqflite_common_ffi','databases'))` —— 一个
/// **相对 `Directory.current`** 的路径，不是「exe 旁边」这个固定位置。双击 exe 时
/// 两者恰好重合，所以看起来像「落在程序目录里」；换个启动方式（快捷方式的
/// 「起始位置」、`flutter run`、文件关联），cwd 就变了，落点跟着变。于是同一个安装
/// 会静默读到另一个空库，用户手上也完全可能有不止一份库。
///
/// 判据只有一条：**数一数盘上有几份**（应用数据目录 + 每个候选落点的**并集**），
/// 出口也只有三个：
/// - 0 份：在应用数据目录新建；
/// - 1 份：不在应用数据目录就搬过去，然后打开；
/// - ≥2 份：逐份只读探查（`database_inspector.dart`）——只有一份读得出来就把其余的
///   归档，不止一份读得出来才交给用户选（`database_conflict_resolver.dart`）。
///
/// **并集**这个口径是有意为之，别退回「应用数据目录那份存在 **且** 至少一个候选落点
/// 也有库」：那样「两份都落在候选侧（cwd 一份、exe 旁一份）、应用数据目录还空着」
/// 会被判成没冲突，然后静默搬一份上去，另一份永远躺在原地。
///
/// 本文件保持纯文件层（只 `stat`），所以能被单元测试直接驱动，也不会有
/// 「扫描过程中开出一个空库」的副作用。
library;

import 'package:path/path.dart' as p;

import 'package:bilimusic/core/storage/database_file_ops.dart';

/// 用户手上的一把库：主库路径 + 同组的旁文件。
///
/// 「一份库」永远是**整组**（主库 + 实际存在的 `-wal` / `-shm` / `-journal`）。
/// 只按主库做判断是本文件存在的意义之一 —— WAL 里可能还有已提交的事务。
class DatabaseFileGroup {
  const DatabaseFileGroup({
    required this.mainPath,
    required this.sidecarPaths,
    required this.size,
    required this.modifiedAt,
  });

  /// 主库路径（`.../playlist.db`）。
  final String mainPath;

  /// 实际存在的旁文件路径，顺序同 [databaseSidecarSuffixes]。
  final List<String> sidecarPaths;

  /// 主库字节数。
  final int size;

  /// 主库最后修改时间。
  final DateTime modifiedAt;

  String get directory => p.dirname(mainPath);
}

/// 弹窗里要对比的表。标签是给用户看的，不出现表名。
///
/// 放在这里而不是探查实现里：它是**对比口径**，UI 与探查都按它走，
/// 而 `database_inspector.dart` 只负责把数字读出来。
const List<({String label, String table})> databaseInspectTables = [
  (label: '当前播放列表', table: 'current_track'),
  (label: '播放历史', table: 'play_history'),
  (label: '收藏', table: 'favorite'),
  (label: '歌单', table: 'playlist'),
  (label: '歌单曲目', table: 'playlist_song'),
];

/// 一份库的只读画像。
class DatabaseStats {
  const DatabaseStats({required this.mainPath, required this.tables});

  final String mainPath;

  /// 表名 → 行数。表不存在时为 null（不同版本的库表集合不一样）。
  final Map<String, int?> tables;

  /// 至少读到了一些表。
  bool get readable => tables.isNotEmpty;

  /// 五张业务表全空 —— 空壳库。文件非空但一条记录都没有，
  /// 这种库会让用户以为数据丢了。
  bool get isShell =>
      readable && tables.values.every((count) => count == null || count == 0);

  /// 读到的行数合计（null 的表按 0 算）；只用来给推荐排序。
  int get rowTotal =>
      tables.values.whereType<int>().fold(0, (sum, count) => sum + count);

  int? countOf(String table) => tables[table];
}

/// 一处落点上的一份库。
class DatabasePlacement {
  const DatabasePlacement({
    required this.directory,
    required this.group,
    this.stats,
  });

  /// 这条记录坐在哪个目录里（候选落点，或应用数据目录）。
  final String directory;

  /// 这一份库本身。
  final DatabaseFileGroup group;

  /// 只读探查出来的行数；没探查或探查失败为 null（UI 显示「读不出来」）。
  final DatabaseStats? stats;

  /// 结构读得出来。**读不出来不等于坏库**：可能是被另一个实例占着、权限不足、
  /// 只读介质、WAL 没 checkpoint，或者是更新版本的 schema。所以它只能当
  /// 「先别选它」的理由，绝不能当「删掉它」的理由。
  bool get readable => stats != null;

  /// 文件非空但一条记录都没有。
  bool get isShell => stats?.isShell ?? false;

  /// 读到的行数合计。
  int get rowTotal => stats?.rowTotal ?? 0;

  DatabasePlacement withStats(DatabaseStats? value) =>
      DatabasePlacement(directory: directory, group: group, stats: value);
}

/// 一次落点扫描的结果。
class DatabaseScan {
  const DatabaseScan({required this.placements, required this.targetDirectory});

  /// 真装着库的落点，**应用数据目录那一份排在最前**（如果它存在）。
  final List<DatabasePlacement> placements;

  /// App 的正式落点（应用数据目录）。
  final String targetDirectory;

  /// 一份都没有 → 应用数据目录新建。
  bool get isEmpty => placements.isEmpty;

  /// 恰好一份 → 不在应用数据目录就搬过去。
  DatabasePlacement? get sole =>
      placements.length == 1 ? placements.first : null;

  /// 应用数据目录那一份；没有则为 null。
  DatabasePlacement? get target {
    for (final placement in placements) {
      if (p.equals(placement.directory, targetDirectory)) return placement;
    }
    return null;
  }

  /// 应用数据目录之外的那些落点。
  List<DatabasePlacement> get others => [
    for (final placement in placements)
      if (!p.equals(placement.directory, targetDirectory)) placement,
  ];

  /// 不止一份 —— 需要用户决定（或者按探查结果自动归档读不出来的那些）。
  bool get isAmbiguous => placements.length > 1;

  /// 结构读得出来的那些落点。
  List<DatabasePlacement> get readable => [
    for (final placement in placements)
      if (placement.readable) placement,
  ];

  /// 给日志用的一句话说明 —— 用户报「莫名其妙弹框」时第一个要看的就是它。
  String describe() {
    if (placements.isEmpty) {
      return '落点扫描：应用数据目录 $targetDirectory（还没有库）；其它落点 无';
    }
    final parts = [
      for (final placement in placements)
        '${placement.directory}(${placement.group.size}B)',
    ];
    return '落点扫描：共 ${placements.length} 份 —— ${parts.join(' , ')}';
  }
}

/// 由宿主事实算出「旧落点」候选目录 —— **每一个都是 sqflite 的 databases 目录那一层**
/// （`absolute(join('.dart_tool','sqflite_common_ffi','databases'))`）。
///
/// 两个候选共用同一套布局，只是**根**不同：
/// - [currentDirectory]：`getDatabasesPath()` 就是以它为根算出来的，也就是
///   「上一次启动的 cwd」；
/// - [executableDirectory]：双击 exe 启动时 cwd 恰好是它，于是那里也攒出过一份。
///   **是带上 sqflite 布局的那个子目录，不是 exe 目录本身** —— sqflite 从来没有
///   把库直接放在 exe 旁边过，按 exe 目录去找只会一次次落空。
///
/// 把 `.dart_tool/sqflite_common_ffi/databases` 写死在这里是另一种错法：sqflite 换了
/// 布局就跟着失效。做法是把 [sqfliteDatabasesPath] 中**相对 cwd 的那一段**原样接到
/// [executableDirectory] 底下（`_reroot`）。接不了（不在 cwd 之下、跨盘符）就只留
/// cwd 那个候选 —— 宁可少猜一个，也不猜一个错的目录。
///
/// 三个入参都得是绝对路径；与 [targetDirectory] 重合的、互相重复的候选会被去掉。
List<String> legacyDatabaseCandidates({
  required String sqfliteDatabasesPath,
  required String currentDirectory,
  required String executableDirectory,
  required String targetDirectory,
}) {
  final candidates = <String?>[
    sqfliteDatabasesPath,
    _reroot(
      sqfliteDatabasesPath,
      from: currentDirectory,
      to: executableDirectory,
    ),
  ];

  final target = p.normalize(targetDirectory);
  final seen = <String>{};
  final result = <String>[];
  for (final candidate in candidates) {
    if (candidate == null) continue;
    final directory = p.normalize(candidate);
    if (p.equals(directory, target)) continue;
    if (!seen.add(p.canonicalize(directory))) continue;
    result.add(directory);
  }
  return result;
}

/// 把 [path] 里相对 [from] 的那一段接到 [to] 底下；接不了（两者不在同一根下，比如
/// 不同盘符）返回 null。
String? _reroot(String path, {required String from, required String to}) {
  final absolute = p.normalize(path);
  final base = p.normalize(from);
  if (!p.equals(base, absolute) && !p.isWithin(base, absolute)) return null;
  return p.join(p.normalize(to), p.relative(absolute, from: base));
}

/// 扫出盘上所有真装着库的落点。
///
/// [candidateDirectories] 是候选**根目录**（即 `.dart_tool/sqflite_common_ffi/databases`
/// 那一层，用 [legacyDatabaseCandidates] 从宿主事实算出来），由调用方给出 —— core
/// 不自己猜 cwd，平台事实由宿主注入。与 [targetDirectory] 相同、或者互相重复的候选
/// 会被去掉。
///
/// 只读：不建目录、不删文件、不开库。某处没有库是正常结论（对应「用户还没在那儿
/// 开过库」），0 字节的同名文件算残渣，也不算一份。
Future<DatabaseScan> scanDatabasePlacements({
  required List<String> candidateDirectories,
  required String targetDirectory,
  required String databaseFileName,
}) async {
  final target = p.normalize(targetDirectory);
  final placements = <DatabasePlacement>[];

  // 应用数据目录那份排在最前：UI 的推荐位、`sole` 的取法都按这个顺序走。
  final targetGroup = await _groupOf(p.join(target, databaseFileName));
  if (targetGroup != null) {
    placements.add(DatabasePlacement(directory: target, group: targetGroup));
  }

  final seen = <String>{};
  for (final raw in candidateDirectories) {
    final directory = p.normalize(raw);
    if (p.equals(directory, target)) continue;
    if (!seen.add(p.canonicalize(directory))) continue;
    final group = await _groupOf(p.join(directory, databaseFileName));
    if (group == null) continue;
    placements.add(DatabasePlacement(directory: directory, group: group));
  }

  return DatabaseScan(placements: placements, targetDirectory: target);
}

/// 主库存在且非空时返回整组，否则返回 null。
Future<DatabaseFileGroup?> _groupOf(String mainPath) async {
  final probe = await probeFile(mainPath);
  if (!probe.isSubstantial) return null;
  return DatabaseFileGroup(
    mainPath: mainPath,
    sidecarPaths: [
      for (final file in databaseFilesOf(mainPath))
        if (file.path != mainPath) file.path,
    ],
    size: probe.size,
    modifiedAt: probe.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}
