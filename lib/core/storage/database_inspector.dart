/// 只读探查一份库里有几条数据 —— 给「两份都有效，该保哪份」提供判据。
///
/// 用户的第一个问题是「这俩里各有什么？」**文件大小答不了这个问题**：一个只建过表、
/// 还没写进任何记录的空壳库也有几十 KB，而用户真正在意的是「我的歌单和收藏还在不在」。
///
/// 数据模型（[DatabaseStats] / [databaseInspectTables] / [DatabaseScan]）在
/// `database_conflict.dart` 里：它们是对比口径，UI 与探查都按它走，
/// 本文件只负责把数字读出来。
///
/// 做法上是**先把整组拷进系统临时目录再开**，理由有两条：
/// - 候选落点那份可能是带 `-wal` 的库，只读打开也可能要在旁边写 `-shm`，直接开
///   有污染用户数据目录的风险；
/// - 探查发生在 `openDatabase` **之前**，绝不能因为「看一眼行数」就在候选落点上
///   留下一个空库。
///
/// 任何一步失败都退化成 `null`（UI 显示「读不出来」），绝不抛给启动路径 ——
/// 探查失败不该让用户连 App 都进不去。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bilimusic/core/storage/database_conflict.dart';

/// 把一次落点扫描里**每一份**都只读探查一遍，返回带上行数的扫描结果。
///
/// 调用方（`database_conflict_resolver.dart`）拿它来判断「是不是只有一份能读」，
/// UI 拿它来画每份里的行数。
Future<DatabaseScan> inspectDatabaseScan(
  DatabaseScan scan, {
  DatabaseFactory? factory,
}) async {
  final inspected = <DatabasePlacement>[];
  for (final placement in scan.placements) {
    inspected.add(
      placement.withStats(
        await inspectDatabaseGroup(placement.group, factory: factory),
      ),
    );
  }
  return DatabaseScan(
    placements: inspected,
    targetDirectory: scan.targetDirectory,
  );
}

/// 拷贝 [group] 到临时目录后只读打开，数各表行数；失败返回 null。
///
/// [factory] 由调用方传（各平台自己的 sqflite factory）：core 层不认平台，
/// 也不去碰全局 `databaseFactory` —— 单元测试里那个全局值是没初始化的。
Future<DatabaseStats?> inspectDatabaseGroup(
  DatabaseFileGroup group, {
  DatabaseFactory? factory,
}) async {
  Directory? scratch;
  try {
    scratch = await Directory.systemTemp.createTemp('bilimusic_db_probe_');
    // 只带主库 + 旁文件，不带 `.bak-` 之类 —— group 里本来就只有整组。
    for (final path in [group.mainPath, ...group.sidecarPaths]) {
      final target = p.join(scratch.path, p.basename(path));
      await File(path).copy(target);
    }

    final scratchPath = p.join(scratch.path, p.basename(group.mainPath));
    // 只读打开：这是别人（可能正在被另一个进程用）的库，我们只是看一眼行数。
    final db = factory == null
        ? await openDatabase(scratchPath, readOnly: true)
        : await factory.openDatabase(
            scratchPath,
            options: OpenDatabaseOptions(readOnly: true),
          );
    try {
      final tables = <String, int?>{};
      for (final entry in databaseInspectTables) {
        tables[entry.table] = await _countRows(db, entry.table);
      }
      return DatabaseStats(mainPath: group.mainPath, tables: tables);
    } finally {
      await db.close();
    }
  } catch (_) {
    return null;
  } finally {
    try {
      await scratch?.delete(recursive: true);
    } catch (_) {
      // 临时目录没删掉不影响结论，系统自己会清。
    }
  }
}

/// 表不存在时返回 null（老版本库没有 downloads 之类的新表）。
Future<int?> _countRows(Database db, String table) async {
  final exists = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: 'type = ? AND name = ?',
    whereArgs: ['table', table],
    limit: 1,
  );
  if (exists.isEmpty) return null;
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
  final value = rows.first['c'];
  return value is int ? value : int.tryParse('$value');
}
