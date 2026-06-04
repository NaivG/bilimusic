import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/bili_fav_folder.dart';
import 'package:bilimusic/models/fav_import_record.dart';
import 'package:bilimusic/services/api_service.dart';
import 'package:bilimusic/managers/playlist_manager.dart';

/// Bilibili 收藏夹同步管理器
/// 职责：
///   - 拉取用户的收藏夹列表（创建 + 收藏）
///   - 遍历收藏夹资源，转换为 Music 对象
///   - 创建/更新本地歌单
///   - 跟踪导入状态
class FavSyncManager extends ChangeNotifier {
  static const String _recordsKey = 'fav_import_records';

  final ApiService _api;
  final PlaylistManager _playlistManager;

  List<FavImportRecord> _records = [];
  bool _isLoading = false;

  FavSyncManager({
    required ApiService api,
    required PlaylistManager playlistManager,
  }) : _api = api,
       _playlistManager = playlistManager;

  /// 当前导入记录
  List<FavImportRecord> get records => List.unmodifiable(_records);

  /// 是否正在加载/同步中
  bool get isLoading => _isLoading;

  /// 根据 folderMediaId 查找导入记录
  FavImportRecord? findRecord(int folderMediaId) {
    try {
      return _records.firstWhere((r) => r.folderMediaId == folderMediaId);
    } catch (_) {
      return null;
    }
  }

  /// 判断收藏夹是否已导入
  bool isImported(int folderMediaId) {
    return _records.any((r) => r.folderMediaId == folderMediaId);
  }

  // ==================== 初始化 ====================

  /// 初始化：从持久化存储恢复导入记录
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        _records = decoded.map((e) => FavImportRecord.fromJson(e)).toList();
      } catch (e) {
        debugPrint('[FavSync] 导入记录解析失败: $e');
        _records = [];
      }
    }
  }

  /// 持久化导入记录
  Future<void> _persistRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_records.map((r) => r.toJson()).toList());
    await prefs.setString(_recordsKey, raw);
  }

  // ==================== 获取收藏夹 ====================

  /// 获取用户所有收藏夹（创建的 + 收藏的，已合并）
  Future<Map<String, List<BiliFavFolder>>> fetchAllFolders(int upMid) async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.fetchUserCreatedFolders(upMid),
        _api.fetchCollectedFolders(upMid),
      ]);

      return {'created': results[0], 'collected': results[1]};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==================== 导入逻辑 ====================

  /// 将收藏夹导入为新的本地歌单
  ///
  /// [folder] - Bilibili 收藏夹
  /// [onProgress] - 进度回调（已处理数，总估算数，失败数）
  /// 返回 [ImportResult]
  Future<ImportResult> importFolderAsNewPlaylist(
    BiliFavFolder folder, {
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    // 1. 创建本地歌单
    final playlistName = folder.title;
    final playlist = await _playlistManager.createPlaylist(
      playlistName,
      source: PlaylistSource.imported,
      description:
          '从 Bilibili 收藏夹导入 · ${folder.folderType == BiliFavFolderType.created ? "创建的" : "收藏的"}',
    );

    // 2. 拉取收藏夹所有资源并导入
    final result = await _collectAndImportSongs(
      folder.mediaId,
      playlist.id,
      playlistName: playlistName,
      onProgress: onProgress,
    );

    // 3. 更新导入记录
    final record = FavImportRecord(
      folderMediaId: folder.mediaId,
      folderTitle: folder.title,
      playlistId: playlist.id,
      lastImportedAt: DateTime.now(),
      importedCount: result.successCount,
      failedCount: result.failedCount,
      status: ImportStatus.synced,
    );
    _records.add(record);
    await _persistRecords();
    notifyListeners();

    return result;
  }

  /// 向已有歌单追加收藏夹内容
  Future<ImportResult> appendFolderToPlaylist(
    BiliFavFolder folder,
    String playlistId, {
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    final result = await _collectAndImportSongs(
      folder.mediaId,
      playlistId,
      playlistName: folder.title,
      onProgress: onProgress,
    );

    // 更新记录
    _updateRecordAfterImport(folder.mediaId, folder.title, playlistId, result);

    return result;
  }

  /// 重新同步单个收藏夹（先删除旧歌曲再导入）
  Future<ImportResult> syncSingleFolder(BiliFavFolder folder) async {
    final record = findRecord(folder.mediaId);
    if (record == null) {
      return ImportResult(successCount: 0, failedCount: 0);
    }

    // 清空旧歌曲
    await _playlistManager.removeSongsFromPlaylist(
      record.playlistId,
      await _playlistManager.loadPlaylistSongs(record.playlistId),
    );

    // 重新导入
    return importFolderAsNewPlaylist(folder);
  }

  /// 同步所有已导入的收藏夹
  Future<SyncSummary> syncAllFolders({
    void Function(String folderTitle, int processed, int total)?
    onFolderProgress,
  }) async {
    int totalSuccess = 0;
    int totalFailed = 0;
    int syncedCount = 0;

    for (final record in _records) {
      if (record.status != ImportStatus.synced) continue;

      // 清空并重新导入
      await _playlistManager.removeSongsFromPlaylist(
        record.playlistId,
        await _playlistManager.loadPlaylistSongs(record.playlistId),
      );

      final result = await _collectAndImportSongs(
        record.folderMediaId,
        record.playlistId,
        playlistName: record.folderTitle,
        onProgress: (processed, total, failed) {
          onFolderProgress?.call(record.folderTitle, processed, total);
        },
      );

      _updateRecordAfterImport(
        record.folderMediaId,
        record.folderTitle,
        record.playlistId,
        result,
      );

      totalSuccess += result.successCount;
      totalFailed += result.failedCount;
      syncedCount++;
    }

    return SyncSummary(
      syncedFolderCount: syncedCount,
      totalSuccess: totalSuccess,
      totalFailed: totalFailed,
    );
  }

  /// 删除导入记录（同时不删除本地歌单，仅解除关联）
  Future<void> removeImportRecord(int folderMediaId) async {
    _records.removeWhere((r) => r.folderMediaId == folderMediaId);
    await _persistRecords();
    notifyListeners();
  }

  // ==================== 内部方法 ====================

  /// 遍历收藏夹所有分页资源，转换为 Music 并导入到歌单
  Future<ImportResult> _collectAndImportSongs(
    int mediaId,
    String playlistId, {
    String playlistName = '',
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    int page = 1;
    int successCount = 0;
    int failedCount = 0;
    int totalEstimated = 0;

    while (true) {
      final resourcePage = await _api.fetchFolderResources(
        mediaId,
        page: page,
        pageSize: 20,
      );

      if (totalEstimated == 0) {
        totalEstimated = resourcePage.mediaCount;
      }

      // 转换资源为 Music 对象
      final songs = <Music>[];
      for (final resource in resourcePage.resources) {
        if (resource.isPlayable) {
          songs.add(_resourceToMusic(resource, playlistName));
          successCount++;
        } else {
          failedCount++;
        }
      }

      // 批量添加到歌单
      if (songs.isNotEmpty) {
        await _playlistManager.addSongsToPlaylist(playlistId, songs);
      }

      onProgress?.call(successCount + failedCount, totalEstimated, failedCount);

      if (!resourcePage.hasMore) break;
      page++;
    }

    return ImportResult(successCount: successCount, failedCount: failedCount);
  }

  /// 将 FavResource 转换为 Music
  Music _resourceToMusic(FavResource resource, String albumName) {
    return Music(
      id: resource.bvid,
      title: resource.title,
      artist: resource.upperName,
      album: albumName,
      coverUrl: resource.cover,
      duration: Duration(seconds: resource.duration),
      audioUrl: '',
    );
  }

  /// 更新导入记录
  void _updateRecordAfterImport(
    int folderMediaId,
    String folderTitle,
    String playlistId,
    ImportResult result,
  ) {
    final index = _records.indexWhere((r) => r.folderMediaId == folderMediaId);
    if (index != -1) {
      _records[index] = _records[index].copyWith(
        lastImportedAt: DateTime.now(),
        importedCount: result.successCount,
        failedCount: result.failedCount,
        status: ImportStatus.synced,
      );
    } else {
      _records.add(
        FavImportRecord(
          folderMediaId: folderMediaId,
          folderTitle: folderTitle,
          playlistId: playlistId,
          lastImportedAt: DateTime.now(),
          importedCount: result.successCount,
          failedCount: result.failedCount,
          status: ImportStatus.synced,
        ),
      );
    }
    _persistRecords();
    notifyListeners();
  }
}

/// 导入结果
class ImportResult {
  final int successCount;
  final int failedCount;

  const ImportResult({required this.successCount, required this.failedCount});
}

/// 全量同步汇总
class SyncSummary {
  final int syncedFolderCount;
  final int totalSuccess;
  final int totalFailed;

  const SyncSummary({
    required this.syncedFolderCount,
    required this.totalSuccess,
    required this.totalFailed,
  });
}
