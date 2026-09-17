// 数据库 schema 自检（开发期工具）。
//
//   dart run tool/db_schema_check.dart [--downgrade]
//
// 用来验证离线缓存引入的 v1 → v2 迁移：
//   - 不传参：只打印 user_version / 各表 / downloads 行数。
//   - 传 --downgrade：把库退回 v1 形态（删 downloads 表、user_version=1），
//     之后启动一次 App 即可验证 onUpgrade 是否真的补建了表。
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final dbPath = p.join(
    Directory.current.path,
    '.dart_tool',
    'sqflite_common_ffi',
    'databases',
    'playlist.db',
  );
  if (!File(dbPath).existsSync()) {
    stderr.writeln('找不到数据库: $dbPath（先跑一次 App 让它建库）');
    exitCode = 1;
    return;
  }

  final db = sqlite3.open(dbPath);
  try {
    if (args.contains('--downgrade')) {
      db.execute('DROP TABLE IF EXISTS downloads');
      db.execute('PRAGMA user_version = 1');
      print('[downgrade] 已退回 v1（downloads 已删、user_version=1）');
    }

    final version = db.select('PRAGMA user_version').first.values.first;
    print('user_version = $version');

    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .map((r) => r['name'])
        .toList();
    print('tables = $tables');

    if (tables.contains('downloads')) {
      final count = db.select('SELECT COUNT(*) AS c FROM downloads').first['c'];
      print('downloads 行数 = $count');
      for (final row in db.select('SELECT * FROM downloads LIMIT 5')) {
        print('  $row');
      }
    } else {
      print('downloads 表缺失');
    }
  } finally {
    db.dispose();
  }
}
