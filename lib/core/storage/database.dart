import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:bilimusic/core/storage/database_conflict.dart';
import 'package:bilimusic/core/storage/database_conflict_resolver.dart';
import 'package:bilimusic/core/storage/database_path_migration.dart';
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

  /// 正在开的那一次（单飞用）。
  Future<Database>? _opening;

  /// 数据库目录解析钩子。
  ///
  /// 默认 `null` → 用 `getDatabasesPath()`，即 sqflite 各平台的原生落点：
  /// Android / iOS 是应用私有目录（本来就安全），Web 是 ffiWeb 的实现。
  /// 桌面端由 `main.dart` 注入 `getApplicationSupportDirectory()`，把库从
  /// sqflite 的默认落点（`Directory.current/.dart_tool/...`）搬到应用数据目录，
  /// 与 `shared_preferences` 同处一地（背景见 [relocateDatabase]）。
  ///
  /// 做成钩子而不是在这里直接 import `path_provider`：`lib/core/` 不引入
  /// Flutter 插件，与 `NetworkConfig.cookieLoader / cookieSaver` 是同一套注入模式。
  static Future<String> Function()? directoryResolver;

  /// 解析过的目标目录（`getApplicationSupportDirectory()` 的返回值）只问一次。
  static String? _resolvedTargetDirectory;

  /// 启动前的落点预检：盘上不止一份库时，把「该保哪份」问清楚。
  ///
  /// 返回非 null 表示**需要用户选择**（每份都带上了只读探查的行数），调用方必须
  /// 弹窗、在用户选完后调 `applyDatabaseChoice` 并**重启进程**；返回 null 表示
  /// 已经处理妥当或本来就没什么可问的（0 份 / 1 份 / 读得出来的只有一份），
  /// 调用方照常往下走。
  ///
  /// **必须排在真 AppShell 起来之前**（见 `main.dart` 的启动顺序）：这样重启进程时
  /// 进程里没有任何状态要收；更重要的是改名归档发生时没有任何东西持有那些 `.db` ——
  /// Windows 上 rename 一个被自己打开的文件是要失败的。
  static Future<DatabaseScan?> preflightDatabaseLocation() async {
    final resolver = directoryResolver;
    // 移动端 / Web：落点本来就是应用私有目录，没有搬迁也没有冲突。
    if (resolver == null) return null;

    // 用户报「莫名其妙的弹框 / 歌单少了一半」时，第一个要看的就是这行。
    debugPrint(
      '[AppDatabase] cwd=${Directory.current.path} '
      'exe=${File(Platform.resolvedExecutable).parent.path}',
    );

    final legacy = await getDatabasesPath();
    final target = await _resolveTargetDirectory(resolver);
    return preflightDatabasePlacement(
      candidateDirectories: _legacyCandidates(legacy, target),
      targetDirectory: target,
      databaseFileName: _dbFileName,
      factory: databaseFactory,
      onLog: (message) => debugPrint('[AppDatabase] $message'),
    );
  }

  /// 开库入口 —— **必须单飞**：同一时刻只允许一次「解析落点 + 开库」。
  ///
  /// 启动路径上有不止一个调用方同时进来：`playlistService.initialize()`
  /// （main.dart:137）与 `unawaited(migrateFromPrefsOnce())`（main.dart:143），
  /// 各自都是 `await AppDatabase.instance.database`。只判 `_db != null` 的话两次都会
  /// 看到 null，于是**两条 `_resolveLocation()` 并发跑**，抢同一份待搬迁的源：
  ///
  /// - 赢的那条把库搬进应用数据目录、删掉旧落点的源；
  /// - 输的那条 `moveFile` 撞上「源已经没了」→ `relocateDatabase` 走失败分支 →
  ///   返回旧落点 → 这里 `openDatabase(旧落点/playlist.db)` 就地建出一个**空壳库**，
  ///   真数据已经在新落点。两个 `Database` 句柄指向两份不同的库，后完成的那个还会
  ///   盖掉 `_db`（2026-09-20 用户现场：应用目录里多出一份 86016 B / 0 行的库）。
  ///
  /// 缓存「在飞的那次」而不是加锁：并发调用方要的是同一个 `Database`，本来就该
  /// 共用一次解析与一次 `openDatabase`。
  Future<Database> get database {
    final opened = _db;
    if (opened != null) return Future.value(opened);
    return _opening ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    try {
      final location = await _resolveLocation();
      final db = await openDatabase(
        p.join(location.directory, _dbFileName),
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
      _db = db;
      return db;
    } finally {
      // 失败时让下一次调用重试；成功时 `_db` 已经顶上。
      _opening = null;
    }
  }

  /// 决定这次把库开在哪个目录，必要时先把候选落点那一份搬过去。
  ///
  /// 走到这里时盘上**最多只剩一份**：不止一份的情况已经在
  /// [preflightDatabaseLocation] 里问过用户、落败的也都改名归档了，重启后的新进程
  /// 同样是从这里开始。所以判据只有一条 —— 那一份在不在应用数据目录：
  /// - 在 → 直接用；
  /// - 不在（落在哪个候选落点都算）→ 搬过去；
  /// - 一份都没有 → 在应用数据目录新建。
  ///
  /// **搬迁源是「扫到的那一份」，而不是「`getDatabasesPath()` 算出来的那个目录」**：
  /// 后者跟着 `Directory.current` 走，而 cwd 会因为启动方式而变。用户先双击 exe 攒出
  /// 一份在程序目录、之后换个 cwd 启动，只认 sqflite 算的那个目录就会一份都看不见，
  /// 于是在应用数据目录开一个空库，让用户以为歌单全没了。
  ///
  /// **必须发生在 `openDatabase` 之前**：先开库会凭空造出一个空库占住目标位置，
  /// 把 [relocateDatabase] 推进「目标已存在」分支，那份数据就被永久挡在外面了。
  Future<DatabaseRelocation> _resolveLocation() async {
    // 问 sqflite 自己的默认落点，而不是把 `.dart_tool/sqflite_common_ffi/databases`
    // 抄死在这里：将来 sqflite 改了布局，这里自动跟着走。这一步是纯字符串
    // 计算，不落盘、不会建目录。
    final legacy = await getDatabasesPath();

    final resolver = directoryResolver;
    if (resolver == null) {
      return DatabaseRelocation(directory: legacy, migrated: false);
    }

    final target = await _resolveTargetDirectory(resolver);
    final scan = await scanDatabasePlacements(
      candidateDirectories: _legacyCandidates(legacy, target),
      targetDirectory: target,
      databaseFileName: _dbFileName,
    );

    final sole = scan.sole;
    if (sole == null) {
      if (scan.isAmbiguous) {
        // 不该发生：不止一份就该在 preflight 里问过用户了。真发生（宿主没走
        // preflight）就保守地退回应用数据目录，并把现场写进日志 —— 这里**不**
        // 静默挑另一份，也不动任何文件。
        debugPrint('[AppDatabase] 落点冲突未经用户选择：${scan.describe()}');
      }
      return DatabaseRelocation(
        directory: target,
        migrated: false,
        reason: scan.isEmpty ? null : '库落点未经选择，本次改用应用数据目录 $target',
      );
    }

    // legacy 与 target 相同时不能调 relocateDatabase：源和目标是同一个文件，
    // `rename` 到自己身上会报错，跨卷兜底路径更糟（拷完把源删掉 = 把库删了）。
    if (p.equals(sole.directory, target)) {
      return DatabaseRelocation(
        directory: target,
        migrated: false,
        reason: '数据库落点已是 $target',
      );
    }

    final relocation = await relocateDatabase(
      legacyDirectory: sole.directory,
      targetDirectory: target,
      databaseFileName: _dbFileName,
    );
    if (relocation.reason != null) {
      debugPrint('[AppDatabase] ${relocation.reason}');
    }
    return relocation;
  }

  /// 候选落点：`Directory.current` 算出来的那个（sqflite 的默认落点），加上 exe
  /// 所在目录底下**同一套布局**的那个。
  ///
  /// 为什么要两个：sqflite 的旧落点**跟着 `Directory.current` 走**，而 cwd 会因为
  /// 启动方式而变。用户先双击 exe 攒出一份在程序目录，后来从别的 cwd 启动又在那个
  /// cwd 下攒出一份 —— 只认其中一个，另一个就会被当成「不存在的旧库」，用户要么被
  /// 莫名弹框、要么数据被静默留在原地。
  ///
  /// 两条路径的算法（含「为什么不是 exe 目录本身」）都在
  /// [legacyDatabaseCandidates] 里，单独放是为了能被测试直接驱动 —— 这段接缝曾经
  /// 错成「`p.dirname(getDatabasesPath())` + exe 目录」，两个候选都打不中真实文件，
  /// 三份库的机器上只扫得出应用数据目录那一份。
  ///
  /// 同样静态：预检要在 `AppDatabase.instance` 之外就能用。
  static List<String> _legacyCandidates(String fromSqflite, String target) =>
      legacyDatabaseCandidates(
        sqfliteDatabasesPath: fromSqflite,
        currentDirectory: Directory.current.path,
        executableDirectory: File(Platform.resolvedExecutable).parent.path,
        targetDirectory: target,
      );

  /// 同时给预检（静态入口，进程还没建起任何东西）和落点解析用，所以是静态的。
  static Future<String> _resolveTargetDirectory(
    Future<String> Function() resolver,
  ) async {
    final cached = _resolvedTargetDirectory;
    if (cached != null) return cached;
    final resolved = await resolver();
    _resolvedTargetDirectory = resolved;
    return resolved;
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
