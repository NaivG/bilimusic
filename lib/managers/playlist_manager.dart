import 'package:flutter/foundation.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/services/playlist_repository.dart';
import 'package:bilimusic/services/playlist_cache.dart';

/// 歌单管理器（单例/门面）
/// 职责：
/// - 作为统一入口暴露给UI层
/// - 管理内存缓存
/// - 协调仓库层和缓存层
/// - 提供便捷的业务方法
class PlaylistManager {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;
  PlaylistManager._internal();

  late PlaylistRepository _repository;
  late MusicCache _cache;
  bool _initialized = false;

  /// 初始化（由main.dart调用一次）
  Future<void> initialize() async {
    if (_initialized) return;

    _repository = PlaylistRepository();
    _cache = MusicCache();
    await _repository.initialize();
    _initialized = true;
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'PlaylistManager has not been initialized. '
        'Call PlaylistManager().initialize() before using.',
      );
    }
  }

  // ==================== 歌单基础操作 ====================

  /// 获取所有歌单（用户歌单，不含歌曲）
  ValueListenable<List<Playlist>> watchUserPlaylists() {
    _ensureInitialized();
    return _repository.watchUserPlaylists();
  }

  /// 获取所有歌单列表
  List<Playlist> get userPlaylists {
    _ensureInitialized();
    return _repository.userPlaylists;
  }

  /// 获取歌单元数据
  Playlist? getPlaylistInfo(String playlistId) {
    _ensureInitialized();
    return _repository.getPlaylistInfo(playlistId);
  }

  /// 获取歌单详情（包含歌曲列表）
  /// 内部处理：先获取歌单元数据，再从缓存/仓库加载歌曲
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    _ensureInitialized();

    // 检查是否为系统歌单
    if (_repository.isSystemPlaylist(playlistId)) {
      return _repository.getSystemPlaylistDetail(playlistId);
    }

    // 获取歌单元数据
    final info = _repository.getPlaylistInfo(playlistId);
    if (info == null) return null;

    // 从缓存获取歌曲（懒加载）
    var songs = _cache.getSongs(playlistId);
    if (songs == null) {
      songs = await _repository.loadPlaylistSongs(playlistId);
      _cache.setSongs(playlistId, songs);
    }

    // 如果歌单没有封面且有歌曲，使用第一首歌的封面
    if ((info.coverUrl == null || info.coverUrl!.isEmpty) && songs.isNotEmpty) {
      await _repository.updatePlaylistCover(playlistId, songs);
      // 重新获取更新后的歌单信息
      final updatedInfo = _repository.getPlaylistInfo(playlistId);
      if (updatedInfo != null) {
        return updatedInfo.copyWith(songs: songs);
      }
    }

    // 合并返回
    return info.copyWith(songs: songs);
  }

  /// 创建歌单
  Future<Playlist> createPlaylist(
    String name, {
    String? description,
    List<String> tagIds = const [],
  }) async {
    _ensureInitialized();
    return _repository.createPlaylist(
      name: name,
      description: description,
      tagIds: tagIds,
    );
  }

  /// 删除歌单（同时清理缓存）
  Future<void> deletePlaylist(String playlistId) async {
    _ensureInitialized();
    _cache.invalidate(playlistId);
    return _repository.deletePlaylist(playlistId);
  }

  /// 重命名歌单
  Future<void> renamePlaylist(String playlistId, String newName) async {
    _ensureInitialized();
    return _repository.updatePlaylistName(playlistId, newName);
  }

  /// 更新歌单描述
  Future<void> updatePlaylistDescription(
    String playlistId,
    String? description,
  ) async {
    _ensureInitialized();
    return _repository.updatePlaylistDescription(playlistId, description);
  }

  /// 添加标签到歌单
  Future<void> addTagToPlaylist(String playlistId, String tagId) async {
    _ensureInitialized();
    return _repository.addTagToPlaylist(playlistId, tagId);
  }

  /// 从歌单移除标签
  Future<void> removeTagFromPlaylist(String playlistId, String tagId) async {
    _ensureInitialized();
    return _repository.removeTagFromPlaylist(playlistId, tagId);
  }

  /// 根据标签筛选歌单
  List<Playlist> filterPlaylistsByTag(String tagId) {
    _ensureInitialized();
    return _repository.filterPlaylistsByTag(tagId);
  }

  // ==================== 歌曲操作 ====================

  /// 添加歌曲到歌单
  Future<bool> addSongsToPlaylist(String playlistId, List<Music> songs) async {
    _ensureInitialized();
    final result = await _repository.addSongsToPlaylist(playlistId, songs);
    if (result) {
      // 清除缓存，下次获取时会重新加载
      _cache.invalidate(playlistId);
    }
    return result;
  }

  /// 从歌单移除歌曲
  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<Music> songs,
  ) async {
    _ensureInitialized();
    await _repository.removeSongsFromPlaylist(playlistId, songs);
    // 清除缓存
    _cache.invalidate(playlistId);
  }

  /// 加载歌单歌曲（从仓库，不使用缓存）
  Future<List<Music>> loadPlaylistSongs(String playlistId) async {
    _ensureInitialized();
    return _repository.loadPlaylistSongs(playlistId);
  }

  // ==================== 收藏操作 ====================

  /// 监听收藏列表
  ValueListenable<List<Music>> watchFavorites() {
    _ensureInitialized();
    return _repository.watchFavorites();
  }

  /// 获取收藏列表
  List<Music> get favorites {
    _ensureInitialized();
    return _repository.favorites;
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(Music music) async {
    _ensureInitialized();
    if (_repository.isFavorite(music)) {
      await _repository.removeFromFavorites(music);
      // 清除收藏歌单缓存
      _cache.invalidate('favorites');
      return false;
    } else {
      await _repository.addToFavorites(music);
      // 清除收藏歌单缓存
      _cache.invalidate('favorites');
      return true;
    }
  }

  /// 添加到收藏
  Future<void> addToFavorites(Music music) async {
    _ensureInitialized();
    await _repository.addToFavorites(music);
    _cache.invalidate('favorites');
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(Music music) async {
    _ensureInitialized();
    await _repository.removeFromFavorites(music);
    _cache.invalidate('favorites');
  }

  /// 检查是否已收藏
  bool isFavorite(Music music) {
    _ensureInitialized();
    return _repository.isFavorite(music);
  }

  // ==================== 播放历史操作 ====================

  /// 监听播放历史
  ValueListenable<List<Music>> watchPlayHistory() {
    _ensureInitialized();
    return _repository.watchPlayHistory();
  }

  /// 获取播放历史
  List<Music> get playHistory {
    _ensureInitialized();
    return _repository.playHistory;
  }

  /// 添加到播放历史
  Future<void> addToHistory(Music music) async {
    _ensureInitialized();
    await _repository.addToHistory(music);
    // 清除历史歌单缓存
    _cache.invalidate('history');
  }

  /// 清空播放历史
  Future<void> clearHistory() async {
    _ensureInitialized();
    await _repository.clearHistory();
    _cache.invalidate('history');
  }

  // ==================== 标签操作 ====================

  /// 监听所有标签
  ValueListenable<List<PlaylistTag>> watchTags() {
    _ensureInitialized();
    return _repository.watchTags();
  }

  /// 获取所有标签（按分类分组）
  Map<TagCategory, List<PlaylistTag>> getTagsByCategory() {
    _ensureInitialized();
    return _repository.getTagsByCategory();
  }

  /// 创建自定义标签
  Future<PlaylistTag> createCustomTag({
    required String name,
    required String nameCn,
    int colorValue = 0xFF636E72,
  }) async {
    _ensureInitialized();
    return _repository.createCustomTag(
      name: name,
      nameCn: nameCn,
      colorValue: colorValue,
    );
  }

  // ==================== 缓存管理 ====================

  /// 预加载歌单歌曲
  Future<void> preloadPlaylistSongs(String playlistId) async {
    _ensureInitialized();
    if (!_cache.hasCache(playlistId)) {
      final songs = await _repository.loadPlaylistSongs(playlistId);
      _cache.setSongs(playlistId, songs);
    }
  }

  /// 清除指定歌单缓存
  void invalidateCache(String playlistId) {
    _ensureInitialized();
    _cache.invalidate(playlistId);
  }

  /// 清除所有缓存
  void clearAllCache() {
    _ensureInitialized();
    _cache.clear();
  }

  /// 检查歌单是否已缓存
  bool hasCache(String playlistId) {
    _ensureInitialized();
    return _cache.hasCache(playlistId);
  }

  // ==================== 向后兼容方法 ====================
  // 以下方法为兼容旧代码保留

  /// 初始化方法（兼容旧代码，建议使用 initialize()）
  Future<void> init() async {
    await initialize();
  }

  /// 获取所有用户歌单（兼容旧代码）
  /// 返回简单的 Playlist 列表（不含 songs）
  List<Playlist> getAllPlaylists() {
    _ensureInitialized();
    return _repository.userPlaylists;
  }

  /// 获取歌单中的歌曲列表（兼容旧代码）
  /// 内部处理缓存
  Future<List<Music>> getPlaylistSongs(String playlistId) async {
    _ensureInitialized();

    // 先检查缓存
    var songs = _cache.getSongs(playlistId);
    if (songs != null) return songs;

    // 检查是否为系统歌单
    if (_repository.isSystemPlaylist(playlistId)) {
      final detail = _repository.getSystemPlaylistDetail(playlistId);
      if (detail != null) {
        songs = detail.songs;
        _cache.setSongs(playlistId, songs);
        return songs;
      }
      return [];
    }

    // 从仓库加载
    songs = await _repository.loadPlaylistSongs(playlistId);
    _cache.setSongs(playlistId, songs);
    return songs;
  }

  /// 添加歌曲到歌单（兼容单首歌方法）
  Future<bool> addSongToPlaylist(String playlistId, Music music) async {
    return addSongsToPlaylist(playlistId, [music]);
  }

  // ==================== 系统歌单 ====================

  /// 检查是否为系统歌单
  bool isSystemPlaylist(String playlistId) {
    _ensureInitialized();
    return _repository.isSystemPlaylist(playlistId);
  }

  /// 获取所有系统歌单
  List<Playlist> get systemPlaylists => DefaultPlaylists.all;
}
