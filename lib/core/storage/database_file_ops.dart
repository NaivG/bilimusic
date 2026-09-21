/// SQLite 库文件组的**文件层操作**：后缀定义、整组统计、移动、归档。
///
/// 从 `database_path_migration.dart` 抽出来，因为一次搬迁（旧落点 → 应用数据目录）
/// 和一次冲突处理（用户选了一份、另一份归档）用的是同一套动作。这里只管文件，
/// 不认平台、不开库、不读 SharedPreferences。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// SQLite 主库之外的旁文件后缀。
///
/// 现在通常是 rollback journal 模式（看不到旁文件），但库一旦被切成 WAL，
/// 已提交的事务可能还躺在 `-wal` 里，只搬主库就会丢数据。
const List<String> databaseSidecarSuffixes = ['-wal', '-shm', '-journal'];

/// 主库 + 实际存在的旁文件，按「旁文件在前、主库在后」排序。
///
/// 这个顺序是有语义的：主库出现与否就是「搬完了」的判据，所以它必须最后动。
List<File> databaseFilesOf(String mainPath) => [
  for (final suffix in databaseSidecarSuffixes)
    if (File('$mainPath$suffix').existsSync()) File('$mainPath$suffix'),
  File(mainPath),
];

/// 0 字节的同名文件视为残渣（上次搬迁被杀在中间留下的），不算「已有数据库」。
Future<bool> isNonEmptyFile(File file) async {
  final stat = await file.stat();
  return stat.type == FileSystemEntityType.file && stat.size > 0;
}

/// 一次 `stat` 的结果；文件不存在时 [exists] 为 false。
class FileProbe {
  const FileProbe._({
    required this.exists,
    required this.size,
    required this.modifiedAt,
  });

  final bool exists;
  final int size;
  final DateTime? modifiedAt;

  /// 文件存在且非 0 字节。
  bool get isSubstantial => exists && size > 0;
}

Future<FileProbe> probeFile(String path) async {
  final stat = await File(path).stat();
  final exists = stat.type == FileSystemEntityType.file;
  return FileProbe._(
    exists: exists,
    size: exists ? stat.size : 0,
    modifiedAt: exists ? stat.modified : null,
  );
}

/// 先试 `rename`（同卷时是原子的）；跨卷会抛 `FileSystemException`
/// （例如源在 `D:`、目标在 `C:`），退化成「拷贝 → 对账长度 → 删源」。
Future<void> moveFile(String from, String to) async {
  try {
    await File(from).rename(to);
    return;
  } on FileSystemException {
    // 交给下面的拷贝路径处理。
  }

  final source = File(from);
  final destination = File(to);
  final original = await source.length();
  await destination.writeAsBytes(await source.readAsBytes(), flush: true);
  final copied = await destination.length();
  if (copied != original) {
    throw FileSystemException('拷贝后长度不一致（$copied != $original）', to);
  }
  await source.delete();
}

/// 把一个库文件组**改名**成 `playlist.db.bak-<时间戳>`，返回新前缀（完整归档
/// 前缀），文件留在原目录 —— 冲突处理里「被放弃的那一份」走这条路。
///
/// 用改名而不是删除：用户在两份之间做选择时最怕的就是「点错了、数据没了」。
/// 改名失败的（极少数，比如文件被占用且跨卷）退化成复制 + 删源，仍失败则整组
/// 回滚并抛错，交给调用方去提示用户 —— **绝不半途而废地留半个库**。
Future<String> archiveDatabaseGroup(String mainPath, {DateTime? now}) async {
  // 归档前缀里不能出现 dbName 后缀，否则 `databaseFilesOf` 之类按 `playlist.db*`
  // 匹配的逻辑会把它当成又一个候选库。
  final stamp = _stamp(now ?? DateTime.now());
  final archived = _uniqueArchivePrefix('$mainPath.bak-$stamp');

  final moves = <(String, String)>[
    for (final file in databaseFilesOf(mainPath))
      (file.path, '$archived${_suffixOf(mainPath, file.path)}'),
  ];

  final done = <(String, String)>[];
  try {
    for (final move in moves) {
      await Directory(p.dirname(move.$2)).create(recursive: true);
      await moveFile(move.$1, move.$2);
      done.add(move);
    }
  } catch (e) {
    for (final move in done.reversed) {
      try {
        await moveFile(move.$2, move.$1);
      } catch (_) {
        // 回滚失败只能靠日志说话：文件位置仍是确定的。
      }
    }
    rethrow;
  }
  return archived;
}

/// 时间戳只到秒，所以同名时可后缀 `-1`、`-2`…：**归档绝不能覆盖已有的归档**，
/// 那等于把上一次让用户「反悔」的机会悄悄抹掉。
String _uniqueArchivePrefix(String base) {
  if (!File(base).existsSync() && !File('$base-wal').existsSync()) return base;
  for (var i = 1; i < 1000; i++) {
    final candidate = '$base-$i';
    if (!File(candidate).existsSync() && !File('$candidate-wal').existsSync()) {
      return candidate;
    }
  }
  return '$base-${DateTime.now().microsecondsSinceEpoch}';
}

/// `20260214T101530`：文件名安全、字典序即时间序。
String _stamp(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}'
      'T'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

String _suffixOf(String mainPath, String filePath) =>
    filePath.substring(mainPath.length);
