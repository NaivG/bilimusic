import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/core/storage/database.dart';
import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';

/// 当前队列的唯一性回归：同一首曲目只允许一条 (bvid, cid) 行。
///
/// 防止 cid 异步回填后，`(bvid,'')` 和 `(bvid,cid)` 两行撞成同一个
/// [Music.key]。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory root;
  late Directory previousCwd;

  Music music({required String id, String cid = '', String title = 'track'}) =>
      Music(
        id: id,
        cid: cid,
        title: title,
        artist: const Artist(name: 'artist'),
        album: 'album',
        coverUrl: '',
        audioUrl: '',
      );

  Future<Database> openDb() => AppDatabase.instance.database;

  Future<void> insertQueueRow(Database db, Music m) async {
    await db.insert('current_track', {
      'music_id': m.id,
      'cid': m.cid,
      'payload': jsonEncode(m.toJson()),
    });
  }

  Future<int> queueRowCount(Database db, String musicId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM current_track WHERE music_id = ?',
      [musicId],
    );
    return rows.first['c']! as int;
  }

  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    previousCwd = Directory.current;
    root = await Directory.systemTemp.createTemp('bilimusic_playlist_');
    Directory.current = root.path;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    // sqflite_common_ffi 的默认落点跟着 cwd 走；每个用例清掉库文件，
    // 避免上一个用例的 current_track 行串进来。
    final dbDir = Directory(
      p.join(root.path, '.dart_tool', 'sqflite_common_ffi', 'databases'),
    );
    if (dbDir.existsSync()) {
      for (final entity in dbDir.listSync()) {
        if (entity is File) await entity.delete();
      }
    }
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
    Directory.current = previousCwd.path;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('加载时清理历史重复行', () {
    test('完全相同的两行只保留一条，并删除落盘重复行', () async {
      final db = await openDb();
      final duplicate = music(id: 'BV1', cid: '123');
      await insertQueueRow(db, duplicate);
      await insertQueueRow(db, duplicate);
      await insertQueueRow(db, music(id: 'BV2', cid: '456'));

      final service = PlaylistService();
      await service.initialize();

      expect(service.currentPlaylist.value.map((m) => m.key).toList(), [
        'BV1_123',
        'BV2_456',
      ]);
      expect(await queueRowCount(db, 'BV1'), 1);
    });

    test('空 cid 与已回填 cid 的两行合并，位置取最早一行', () async {
      final db = await openDb();
      final pending = music(id: 'BV1', title: 'pending');
      final detailed = music(id: 'BV1', cid: '123', title: 'detailed');
      await insertQueueRow(db, pending);
      await insertQueueRow(db, music(id: 'BV2', cid: '456'));
      await insertQueueRow(db, detailed);

      final service = PlaylistService();
      await service.initialize();

      expect(service.currentPlaylist.value.length, 2);
      expect(service.currentPlaylist.value[0].id, 'BV1');
      expect(service.currentPlaylist.value[0].cid, '123');
      expect(service.currentPlaylist.value[0].title, 'detailed');
      expect(service.currentPlaylist.value[1].id, 'BV2');
      expect(await queueRowCount(db, 'BV1'), 1);

      final rows = await db.query('current_track', orderBy: 'seq ASC');
      expect(rows.map((r) => r['music_id']), ['BV1', 'BV2']);
      expect(rows.first['cid'], '123');
    });

    test('同 bvid 的不同分P保留为两条', () async {
      final db = await openDb();
      await insertQueueRow(db, music(id: 'BV1', cid: '1'));
      await insertQueueRow(db, music(id: 'BV1', cid: '2'));

      final service = PlaylistService();
      await service.initialize();

      expect(service.currentPlaylist.value.length, 2);
      expect(await queueRowCount(db, 'BV1'), 2);
    });
  });

  group('追加时不再制造重复', () {
    test('已回填 cid 的队列项会吸收同 bvid 的空 cid 版本', () async {
      final db = await openDb();
      final service = PlaylistService();
      await service.initialize();

      await service.addToPlaylist(music(id: 'BV1', cid: '123'));
      await service.addToPlaylist(music(id: 'BV1'));

      expect(service.currentPlaylist.value.length, 1);
      expect(service.currentPlaylist.value.single.cid, '123');
      expect(await queueRowCount(db, 'BV1'), 1);
    });

    test('空 cid 队列项被详情版本原地补全，而不是追加第二条', () async {
      final db = await openDb();
      final service = PlaylistService();
      await service.initialize();

      await service.addToPlaylist(music(id: 'BV1'));
      await service.addToPlaylist(music(id: 'BV1', cid: '123'));

      expect(service.currentPlaylist.value.length, 1);
      expect(service.currentPlaylist.value.single.cid, '123');
      expect(await queueRowCount(db, 'BV1'), 1);
    });

    test('并发追加同一首仍然只有一条', () async {
      final db = await openDb();
      final service = PlaylistService();
      await service.initialize();

      await Future.wait([
        service.addToPlaylist(music(id: 'BV1', cid: '123')),
        service.addToPlaylist(music(id: 'BV1', cid: '123')),
      ]);

      expect(service.currentPlaylist.value.length, 1);
      expect(await queueRowCount(db, 'BV1'), 1);
    });

    test('批量追加去重后按顺序拼接到当前队列末尾', () async {
      final service = PlaylistService();
      await service.initialize();

      await service.addToPlaylist(music(id: 'BV1', cid: '1'));
      await service.addAllToPlaylist([
        music(id: 'BV2', cid: '2'),
        music(id: 'BV1', cid: '1'),
        music(id: 'BV3', cid: '3'),
      ]);

      expect(service.currentPlaylist.value.map((m) => m.key).toList(), [
        'BV1_1',
        'BV2_2',
        'BV3_3',
      ]);
    });
  });

  group('备份导入导出', () {
    test('当前队列、自定义标签和 kv 表可往返', () async {
      final service = PlaylistService();
      await service.initialize();

      await service.addToPlaylist(music(id: 'BV1', cid: '1'));
      await service.addToPlaylist(music(id: 'BV2', cid: '2'));
      final tag = await service.createCustomTag(name: 'night', nameCn: '夜晚');
      await AppDatabase.instance.kvSet('taste_profile_v1', '{"v":1}');

      final backup = await service.exportForBackup();
      expect(backup['current_queue'], isNotNull);
      expect(backup['custom_tags'], contains(tag.id));
      expect(backup['kv'], contains('taste_profile_v1'));

      await service.clearAllUserData();
      expect(service.currentPlaylist.value, isEmpty);
      expect(service.getTagById(tag.id), isNull);
      expect(await AppDatabase.instance.kvGet('taste_profile_v1'), isNull);

      await service.importFromBackup(backup.cast<String, dynamic>());

      expect(service.currentPlaylist.value.map((m) => m.key).toList(), [
        'BV1_1',
        'BV2_2',
      ]);
      expect(service.getTagById(tag.id)?.nameCn, '夜晚');
      expect(await AppDatabase.instance.kvGet('taste_profile_v1'), '{"v":1}');
    });

    test('旧备份没有 kv 时保留本机口味画像', () async {
      final service = PlaylistService();
      await service.initialize();
      await AppDatabase.instance.kvSet('taste_profile_v1', '{"local":true}');

      await service.importFromBackup(<String, dynamic>{
        'play_history': '[]',
        'favorites': '[]',
      });

      expect(
        await AppDatabase.instance.kvGet('taste_profile_v1'),
        '{"local":true}',
      );
    });
  });
}
