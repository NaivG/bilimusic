import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/core/storage/database.dart';
import 'package:bilimusic/domain/bili_fav_folder.dart';
import 'package:bilimusic/domain/bili_fav_resource.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/fav_sync/fav_sync_manager.dart';
import 'package:bilimusic/features/fav_sync/models/fav_import_record.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';

/// 收藏夹只按 mediaId 提供全部资源，忽略分页。
class _FakeApi implements ApiService {
  final Map<int, List<FavResource>> resourcesByFolder = {};

  @override
  Future<FavResourcePage> fetchFolderResources(
    int mediaId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final all = resourcesByFolder[mediaId] ?? const <FavResource>[];
    return FavResourcePage(
      resources: all,
      hasMore: false,
      mediaCount: all.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('${invocation.memberName}');
  }
}

/// 每个收藏夹只对应一个本地歌单和一条导入记录。
///
/// 防回归：「重新同步」清空旧歌单后必须复用同一个歌单，不能新建歌单、
/// 也不能追加第二条记录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory root;
  late Directory previousCwd;
  late _FakeApi api;
  late PlaylistService playlistService;
  late FavSyncManager manager;

  const folder = BiliFavFolder(mediaId: 100, fid: 1, mid: 1, title: '我的收藏夹');

  FavResource resource(String bvid) => FavResource(
    id: bvid.hashCode,
    type: 2,
    title: bvid,
    bvid: bvid,
    upperMid: 1,
    upperName: 'UP 主',
    duration: 120,
  );

  List<Playlist> importedPlaylists() => playlistService.userPlaylistsSnapshot
      .where((p) => p.source == PlaylistSource.imported)
      .toList();

  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    previousCwd = Directory.current;
    root = await Directory.systemTemp.createTemp('bilimusic_fav_sync_');
    Directory.current = root.path;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppDatabase.instance.close();
    // sqflite_common_ffi 的默认落点跟着 cwd 走，每个用例清掉库文件。
    final dbDir = Directory(
      p.join(root.path, '.dart_tool', 'sqflite_common_ffi', 'databases'),
    );
    if (dbDir.existsSync()) {
      for (final entity in dbDir.listSync()) {
        if (entity is File) await entity.delete();
      }
    }

    api = _FakeApi();
    playlistService = PlaylistService();
    await playlistService.initialize();
    manager = FavSyncManager(api: api, playlistService: playlistService);
    await manager.initialize();
  });

  tearDown(() async {
    manager.dispose();
    await playlistService.dispose();
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
    Directory.current = previousCwd.path;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('首次导入创建一个歌单和一条记录', () async {
    api.resourcesByFolder[folder.mediaId] = [resource('BV1'), resource('BV2')];

    final result = await manager.importFolderAsNewPlaylist(folder);

    expect(result.successCount, 2);
    expect(importedPlaylists(), hasLength(1));
    expect(manager.records, hasLength(1));
    expect(manager.records.single.playlistId, importedPlaylists().single.id);
  });

  test('重新同步复用原歌单，不会多出歌单或记录', () async {
    api.resourcesByFolder[folder.mediaId] = [resource('BV1'), resource('BV2')];
    await manager.importFolderAsNewPlaylist(folder);
    final playlistId = manager.records.single.playlistId;

    // 收藏夹里删掉一首、新增一首
    api.resourcesByFolder[folder.mediaId] = [resource('BV2'), resource('BV3')];
    final result = await manager.syncSingleFolder(folder);

    expect(result.successCount, 2);
    expect(importedPlaylists(), hasLength(1));
    expect(importedPlaylists().single.id, playlistId);
    expect(manager.records, hasLength(1));
    expect(manager.records.single.playlistId, playlistId);
    expect(manager.records.single.importedCount, 2);

    final songs = await playlistService.loadPlaylistSongs(playlistId);
    expect(songs.map((m) => m.id).toList(), ['BV2', 'BV3']);
    expect(importedPlaylists().single.songCount, 2);
  });

  test('重复导入同一收藏夹不会追加第二条记录', () async {
    api.resourcesByFolder[folder.mediaId] = [resource('BV1')];
    await manager.importFolderAsNewPlaylist(folder);
    final firstPlaylistId = manager.records.single.playlistId;

    // createPlaylist 的 id 取毫秒时间戳，拉开一点避免撞 id。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await manager.importFolderAsNewPlaylist(folder);

    expect(manager.records, hasLength(1));
    expect(manager.records.single.playlistId, isNot(firstPlaylistId));
  });

  test('原歌单被本地删除后重新同步会重建歌单，记录不重复', () async {
    api.resourcesByFolder[folder.mediaId] = [resource('BV1')];
    await manager.importFolderAsNewPlaylist(folder);
    final oldPlaylistId = manager.records.single.playlistId;
    await playlistService.deletePlaylist(oldPlaylistId);

    api.resourcesByFolder[folder.mediaId] = [resource('BV1'), resource('BV2')];
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await manager.syncSingleFolder(folder);

    expect(importedPlaylists(), hasLength(1));
    final rebuilt = importedPlaylists().single;
    expect(rebuilt.id, isNot(oldPlaylistId));
    expect(manager.records, hasLength(1));
    expect(manager.records.single.playlistId, rebuilt.id);
    expect(await playlistService.loadPlaylistSongs(rebuilt.id), hasLength(2));
  });

  test('初始化时按收藏夹去重历史记录，保留最近一次导入', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      FavSyncManager.prefsKey,
      jsonEncode([
        for (final entry in [
          ('playlist_old', 1000),
          ('playlist_mid', 2000),
          ('playlist_new', 3000),
        ])
          FavImportRecord(
            folderMediaId: folder.mediaId,
            folderTitle: folder.title,
            playlistId: entry.$1,
            lastImportedAt: DateTime.fromMillisecondsSinceEpoch(entry.$2),
            importedCount: 1,
            status: ImportStatus.synced,
          ).toJson(),
      ]),
    );

    final restored = FavSyncManager(api: api, playlistService: playlistService);
    await restored.initialize();

    expect(restored.records, hasLength(1));
    expect(restored.records.single.playlistId, 'playlist_new');

    final persisted =
        jsonDecode(prefs.getString(FavSyncManager.prefsKey)!) as List;
    expect(persisted, hasLength(1));
    restored.dispose();
  });
}
