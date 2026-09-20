/// sqflite 旧落点的一次性迁移。
///
/// 搬迁源固定是 [relocateDatabase] 的 `legacyDirectory` **一个**目录：真实用户
/// 每次启动的 cwd 都一样（就是 exe 目录），不存在「到处找库」的必要，开发机上
/// 因为换启动方式攒出来的多个库手动拷一份即可，不值得在启动路径上扫目录。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:bilimusic/core/storage/database_file_ops.dart';

/// 一次落点解析的结果。
class DatabaseRelocation {
  const DatabaseRelocation({
    required this.directory,
    required this.migrated,
    this.reason,
  });

  /// 最终该用来开库的目录。
  ///
  /// 搬迁成功时是目标目录；没搬（不需要搬，或者**搬不动**）时是实际能用的那个
  /// —— 搬不动就退回旧落点，绝不返回一个空着的目标目录。
  final String directory;

  /// 本次是否真的搬了文件。
  final bool migrated;

  /// 给日志用的一句话说明；无需说明时为 null。
  final String? reason;
}

/// 把 [legacyDirectory] 里的 [databaseFileName]（含旁文件）搬到 [targetDirectory]。
///
/// 幂等，可重复调用：
/// - 两个目录相同（移动端 / Web，或用户把数据目录指到了旧落点）→ 直接返回；
/// - 旧落点没有库 → 什么都不做，直接用目标目录（目标目录由 `openDatabase`
///   自己按需创建）；
/// - 目标已有**非空**库 → 一律以目标为准，不覆盖；空文件视为残渣，照搬。
///
/// 搬迁顺序是**先旁文件、后主库**：主库出现与否就是「搬完了」的判据。任何一步
/// 失败都会把已经搬过去的文件搬回来，然后**返回「哪边真的有一份非空主库」的那一边**
/// （见 [directoryAfterFailedRelocation]）——「退回旧落点」不是无条件的：旧落点的源可能
/// 已经被并发的另一次搬迁搬走并删掉，那时退回旧落点就是退回一个空目录，调用方会在
/// 那里开出一个空壳库，而真数据在新落点。两边都没有库时用目标目录：宁可这次在新
/// 地方开库（全新安装本来就走这条路），也不在这种状态下去旧落点长出一个空壳。
///
/// 为什么"不能在新地方开出一个空库"仍然是铁律：老用户的
/// `sqflite_migration_v1_done` 早已置位，`AppDatabase.migrateFromPrefsOnce()` 会直接
/// 返回，prefs 里的旧数据也早被清掉，开空库等于让用户看到「歌单全没了」。所以
/// 「目标已存在非空库 → 不覆盖」这条判据必须留着：那时目标里那份才是用户的库。
Future<DatabaseRelocation> relocateDatabase({
  required String legacyDirectory,
  required String targetDirectory,
  required String databaseFileName,
}) async {
  final legacy = p.normalize(legacyDirectory);
  final target = p.normalize(targetDirectory);

  if (p.equals(legacy, target)) {
    return DatabaseRelocation(
      directory: legacy,
      migrated: false,
      reason: '数据库落点已是 $legacy',
    );
  }

  final source = File(p.join(legacy, databaseFileName));
  if (!await source.exists()) {
    return DatabaseRelocation(
      directory: target,
      migrated: false,
      reason: '旧落点没有数据库文件（$legacy），本次直接使用 $target',
    );
  }

  final destination = File(p.join(target, databaseFileName));
  if (await isNonEmptyFile(destination)) {
    return DatabaseRelocation(
      directory: target,
      migrated: false,
      reason: '目标已存在数据库（$target），保留现有文件不覆盖',
    );
  }

  // 先旁文件、后主库：`databaseFilesOf` 的顺序就是搬迁顺序。
  final moves = <(String, String)>[
    for (final file in databaseFilesOf(source.path))
      (
        file.path,
        '${destination.path}${file.path.substring(source.path.length)}',
      ),
  ];

  final done = <(String, String)>[];
  try {
    await Directory(target).create(recursive: true);
    for (final move in moves) {
      await moveFile(move.$1, move.$2);
      done.add(move);
    }
  } catch (e) {
    for (final move in done.reversed) {
      try {
        await moveFile(move.$2, move.$1);
      } catch (_) {
        // 回滚失败只能靠日志说话：文件位置仍是确定的，就在目标目录里。
      }
    }
    final directory = await directoryAfterFailedRelocation(
      legacy: legacy,
      target: target,
      databaseFileName: databaseFileName,
    );
    return DatabaseRelocation(
      directory: directory,
      migrated: false,
      reason: p.equals(directory, target)
          ? '搬到 $target 失败（$e）；该用的那份在 $target，本次使用 $target'
          : '搬到 $target 失败（$e），本次继续使用旧落点 $legacy',
    );
  }

  return DatabaseRelocation(
    directory: target,
    migrated: true,
    reason: '数据库已从 $legacy 搬到 $target（共 ${done.length} 个文件）',
  );
}

/// 搬失败之后这次到底该开哪个目录 —— **绝不返回一个没有库的落点**。
///
/// 「搬不动就退回旧落点」这条兜底有个前提：旧落点里**还有那份库**。回滚保证不了
/// 它 —— `done` 为空（一个文件都还没搬成）时回滚无事可做，而源可能已经不在了：
/// 并发的另一次搬迁已经把它搬走并删掉，或者用户自己把文件挪走了。这时退回旧落点
/// 等于退回一个空目录，调用方紧接着 `openDatabase(旧落点/playlist.db)` 就会
/// **就地建出一个空壳库**，而真数据已经在应用数据目录里（2026-09-20 用户现场：
/// 应用目录里多出一份 86016 B、8 张表全 0 行的库，正是 `onCreate` 建出来的）。
///
/// 判据只有一条：哪边**真的有一份非空的主库**就用哪边。
/// - 目标有 → 用目标（并发赢家刚搬完的那份，或本来就在那儿的）；
/// - 只有旧落点有 → 用旧落点（真没搬动，原地继续最安全）；
/// - 两边都没有 → 用目标：它是 App 的正式落点，在那里新建比留在旧落点强
///   （旧落点正是这一版要废弃的位置，再让它长出库来就是走回头路）。
///
/// 公开是为了能被测试直接驱动（四种状态各一条），见
/// `test/storage/database_relocation_fallback_test.dart`。
Future<String> directoryAfterFailedRelocation({
  required String legacy,
  required String target,
  required String databaseFileName,
}) async {
  if (await isNonEmptyFile(File(p.join(target, databaseFileName)))) {
    return target;
  }
  if (await isNonEmptyFile(File(p.join(legacy, databaseFileName)))) {
    return legacy;
  }
  return target;
}
