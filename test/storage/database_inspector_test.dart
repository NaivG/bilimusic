import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/core/storage/database_conflict.dart';
import 'package:bilimusic/core/storage/database_inspector.dart';

/// 只读探查的行为密封测试。
///
/// 它存在的唯一理由：**文件大小会骗人** —— 一个只建过表、还没写进任何记录的空壳
/// 库也有几十 KB，而用户要的是「我的歌单和收藏还在不在」。所以这里要钉死：
/// 行数能数对、空壳能被认出来、缺表算「读到了 0」而不是「读不出来」、
/// 损坏文件退化成 null 而不是抛出去（探查失败不该让用户连 App 都进不去）、
/// 以及探查过程**不碰原文件**。
void main() {
  sqfliteFfiInit();

  late Directory root;
  late String dbPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bilimusic_inspect_');
    dbPath = p.join(root.path, 'playlist.db');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  const tables = [
    'current_track',
    'play_history',
    'favorite',
    'playlist',
    'playlist_song',
  ];

  /// 造库：[counts] 指定每张表的行数，缺的表不建。
  ///
  /// `singleInstance: false` + 先删旧文件：sqflite ffi 的 factory 会复用同路径的
  /// `singleInstance` 连接，而只读探查是**另开一个连接读副本**，留着旧连接会让
  /// 「造库」这一步拿到旧连接、`onCreate` 不执行。
  Future<void> makeDatabase(Map<String, int> counts) async {
    if (File(dbPath).existsSync()) {
      await databaseFactoryFfi.deleteDatabase(dbPath);
    }
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        onCreate: (db, _) async {
          for (final entry in counts.entries) {
            await db.execute(
              'CREATE TABLE ${entry.key} (id INTEGER PRIMARY KEY)',
            );
            for (var i = 0; i < entry.value; i++) {
              await db.insert(entry.key, {'id': i + 1});
            }
          }
        },
      ),
    );
    await db.close();
  }

  Future<DatabaseStats?> inspect() async {
    final stat = File(dbPath).statSync();
    return inspectDatabaseGroup(
      DatabaseFileGroup(
        mainPath: dbPath,
        sidecarPaths: const [],
        size: stat.size,
        modifiedAt: stat.modified,
      ),
      factory: databaseFactoryFfi,
    );
  }

  test('行数数得对，五张表都在', () async {
    await makeDatabase({
      'current_track': 4,
      'play_history': 12,
      'favorite': 30,
      'playlist': 2,
      'playlist_song': 88,
    });

    final stats = await inspect();

    expect(stats, isNotNull);
    expect(stats!.countOf('current_track'), 4);
    expect(stats.countOf('play_history'), 12);
    expect(stats.countOf('favorite'), 30);
    expect(stats.countOf('playlist'), 2);
    expect(stats.countOf('playlist_song'), 88);
  });

  test('只建了表、一条记录都没有 → 认成空壳（哪怕文件有几十 KB）', () async {
    await makeDatabase({for (final table in tables) table: 0});

    final stats = await inspect();

    expect(stats, isNotNull);
    expect(
      File(dbPath).statSync().size,
      greaterThan(0),
      reason: '文件确实非空 —— 这正是「按大小判断」会踩的坑',
    );
    expect(stats!.isShell, isTrue, reason: '非空文件 + 零行 = 空壳');
  });

  test('有任意一张表非空 → 不是空壳', () async {
    await makeDatabase({'current_track': 0, 'favorite': 1});

    final stats = await inspect();

    expect(stats!.isShell, isFalse);
    expect(stats.countOf('favorite'), 1);
  });

  test('缺表算「读到了 0 行」而不是「读不出来」', () async {
    await makeDatabase({'favorite': 3});

    final stats = await inspect();

    expect(stats, isNotNull);
    expect(stats!.readable, isTrue);
    expect(stats.countOf('current_track'), isNull, reason: '表不存在 → 显示为 —');
    expect(stats.countOf('favorite'), 3);
    expect(stats.isShell, isFalse);
  });

  test('文件是垃圾字节 → 返回 null，不抛', () async {
    await File(dbPath).writeAsBytes(List<int>.generate(4096, (i) => i % 251));

    final stats = await inspect();

    expect(stats, isNull);
  });

  test('主库不存在 → 返回 null，不抛', () async {
    final stats = await inspect();

    expect(stats, isNull);
  });

  test('探查不碰原文件：内容与 mtime 都不变，也不在旁边留 -wal/-shm', () async {
    await makeDatabase({'favorite': 7});
    final before = File(dbPath).statSync();
    final bytesBefore = await File(dbPath).readAsBytes();

    final stats = await inspect();

    expect(stats, isNotNull);
    final after = File(dbPath).statSync();
    expect(after.size, before.size);
    expect(after.modified, before.modified);
    expect(await File(dbPath).readAsBytes(), bytesBefore);
    expect(
      Directory(root.path).listSync().map((e) => p.basename(e.path)).toList(),
      ['playlist.db'],
      reason: '探查用的副本放在系统临时目录，不许在原目录留痕',
    );
  });
}
