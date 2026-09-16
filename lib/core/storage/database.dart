import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/domain/playlist_tag.dart';

/// sqflite 单例
/// 文件名: playlist.db
/// 数据来源: 原 playlist_service.dart + playlist_repository.dart 合并后的共享存储
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String _dbFileName = 'playlist.db';
  static const int _version = 2;
  static const String _migrationFlagKey = 'sqflite_migration_v1_done';

  /// v2 新增：离线缓存（downloads 表）。
  /// 注意：此后每加一张表，`_onCreate` 与 `_onUpgrade` **两处都要补**——
  /// 新装用户走 onCreate，老用户走 onUpgrade，漏一处就会出现"表不存在"。
  static const int _versionWithDownloads = 2;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = await getDatabasesPath();
    _db = await openDatabase(
      '$path/$_dbFileName',
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE IF NOT EXISTS playlist (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        cover_url TEXT,
        song_count INTEGER DEFAULT 0,
        total_duration_sec INTEGER DEFAULT 0,
        tag_ids TEXT,
        source TEXT NOT NULL,
        play_count INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_played_at INTEGER,
        is_default INTEGER DEFAULT 0,
        created_by TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS playlist_song (
        playlist_id TEXT NOT NULL,
        music_id TEXT NOT NULL,
        cid TEXT,
        position INTEGER NOT NULL,
        payload TEXT NOT NULL,
        added_at INTEGER,
        added_from TEXT,
        PRIMARY KEY (playlist_id, music_id, cid)
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_playlist_song_pl '
      'ON playlist_song(playlist_id, position)',
    );

    batch.execute('''
      CREATE TABLE IF NOT EXISTS favorite (
        music_id TEXT NOT NULL,
        cid TEXT,
        payload TEXT NOT NULL,
        added_at INTEGER,
        PRIMARY KEY (music_id, cid)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS play_history (
        music_id TEXT NOT NULL,
        cid TEXT,
        payload TEXT NOT NULL,
        played_at INTEGER,
        PRIMARY KEY (music_id, cid)
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_play_history_time '
      'ON play_history(played_at DESC)',
    );

    batch.execute('''
      CREATE TABLE IF NOT EXISTS current_track (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        music_id TEXT NOT NULL,
        cid TEXT,
        payload TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_current_track_seq '
      'ON current_track(seq)',
    );

    batch.execute('''
      CREATE TABLE IF NOT EXISTS kv (
        k TEXT PRIMARY KEY,
        v TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS custom_tag (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');

    _createDownloadsTable(batch);

    await batch.commit(noResult: true);
  }

  /// 离线缓存索引表。
  ///
  /// 主键 (bvid, cid)：与 [Music.key] 同一判等语义，多 P 视频按分 P 各存一份。
  /// 只存"文件在哪、什么音质、多大"，音频本体是用户可见的普通文件，不进数据库。
  void _createDownloadsTable(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
        bvid TEXT NOT NULL,
        cid TEXT NOT NULL,
        title TEXT,
        artist TEXT,
        file_path TEXT NOT NULL,
        quality_id TEXT,
        file_size INTEGER DEFAULT 0,
        downloaded_at INTEGER NOT NULL,
        PRIMARY KEY (bvid, cid)
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_downloads_time '
      'ON downloads(downloaded_at DESC)',
    );
  }

  /// 数据库升级。
  ///
  /// [oldVersion] < 2 都补建 downloads 表：早期版本没有版本号迁移链，
  /// 任何比 2 小的版本都缺这张表，统一按"补建"处理最稳。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    final batch = db.batch();
    if (oldVersion < _versionWithDownloads) {
      _createDownloadsTable(batch);
    }
    await batch.commit(noResult: true);
    debugPrint('[AppDatabase] upgraded $oldVersion -> $newVersion');
  }

  /// 一次性迁移：把旧 SharedPreferences 里残留的列表数据塞到 sqflite 里, 并删除旧 key。
  /// 幂等：通过 `sqflite_migration_v1_done` 标记保证只跑一次。
  Future<void> migrateFromPrefsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationFlagKey) == true) return;

    final db = await database;
    final hasLegacy =
        prefs.getString('playlist') != null ||
        prefs.getString('play_history') != null ||
        prefs.getString('favorites') != null ||
        prefs.getString('user_playlists_enhanced') != null ||
        prefs.getString('custom_tags') != null ||
        prefs.getKeys().any(
          (k) =>
              k.startsWith('playlist_songs_') || k.startsWith('playlist_info_'),
        );

    if (hasLegacy) {
      await db.transaction((txn) async {
        await _migrateCurrentPlaylist(txn, prefs);
        await _migratePlayHistory(txn, prefs);
        await _migrateFavorites(txn, prefs);
        await _migrateUserPlaylists(txn, prefs);
        await _migratePlaylistSongs(txn, prefs);
        await _migrateCustomTags(txn, prefs);
      });
    }

    for (final key in prefs.getKeys().toList()) {
      if (key == _migrationFlagKey) continue;
      if (key == 'playlist' ||
          key == 'play_history' ||
          key == 'favorites' ||
          key == 'user_playlists' ||
          key == 'user_playlists_enhanced' ||
          key == 'custom_tags' ||
          key.startsWith('playlist_songs_') ||
          key.startsWith('playlist_info_')) {
        await prefs.remove(key);
      }
    }

    await prefs.setBool(_migrationFlagKey, true);
    debugPrint(
      '[AppDatabase] migration complete (legacy keys cleaned, db=$_dbFileName)',
    );
  }

  Future<void> _migrateCurrentPlaylist(
    Transaction txn,
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString('playlist');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final r in list) {
        try {
          final m = Music.fromJson(r as Map<String, dynamic>);
          await txn.insert('current_track', {
            'music_id': m.id,
            'cid': m.cid,
            'payload': jsonEncode(m.toJson()),
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _migratePlayHistory(
    Transaction txn,
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString('play_history');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      var ts = DateTime.now().millisecondsSinceEpoch;
      for (final r in list) {
        try {
          final m = Music.fromJson(r as Map<String, dynamic>);
          await txn.insert('play_history', {
            'music_id': m.id,
            'cid': m.cid,
            'payload': jsonEncode(m.toJson()),
            'played_at': ts--,
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _migrateFavorites(
    Transaction txn,
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString('favorites');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final r in list) {
        try {
          final m = Music.fromJson(r as Map<String, dynamic>);
          await txn.insert('favorite', {
            'music_id': m.id,
            'cid': m.cid,
            'payload': jsonEncode(m.toJson()),
            'added_at': now,
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _migrateUserPlaylists(
    Transaction txn,
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString('user_playlists_enhanced');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final r in list) {
        try {
          final p = Playlist.fromJson(r as Map<String, dynamic>);
          await txn.insert('playlist', _playlistRow(p));
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _migratePlaylistSongs(
    Transaction txn,
    SharedPreferences prefs,
  ) async {
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('playlist_songs_')) continue;
      final playlistId = key.substring('playlist_songs_'.length);
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final list = jsonDecode(raw) as List;
        var pos = 0;
        for (final r in list) {
          try {
            final m = Music.fromJson(r as Map<String, dynamic>);
            await txn.insert('playlist_song', {
              'playlist_id': playlistId,
              'music_id': m.id,
              'cid': m.cid,
              'position': pos++,
              'payload': jsonEncode(m.toJson()),
              'added_at': DateTime.now().millisecondsSinceEpoch,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  Future<void> _migrateCustomTags(
    Transaction txn,
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString('custom_tags');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final r in list) {
        try {
          final t = PlaylistTag.fromJson(r as Map<String, dynamic>);
          await txn.insert('custom_tag', {
            'id': t.id,
            'payload': jsonEncode(t.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Map<String, Object?> _playlistRow(Playlist p) => {
    'id': p.id,
    'name': p.name,
    'description': p.description,
    'cover_url': p.coverUrl,
    'song_count': p.songCount,
    'total_duration_sec': p.totalDuration.inSeconds,
    'tag_ids': jsonEncode(p.tagIds),
    'source': p.source.name,
    'play_count': p.playCount,
    'created_at': p.createdAt.millisecondsSinceEpoch,
    'updated_at': p.updatedAt.millisecondsSinceEpoch,
    'last_played_at': p.lastPlayedAt?.millisecondsSinceEpoch,
    'is_default': p.isDefault ? 1 : 0,
    'created_by': p.createdBy,
  };
}
