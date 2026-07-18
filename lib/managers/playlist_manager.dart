import 'package:flutter/foundation.dart';

import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/services/playlist_service.dart';

/// 歌单管理器的 UI 门面。
///
/// 在 sqflite 统一存储之前，这里曾经包装 `PlaylistRepository` + `MusicCache`，但 `MusicCache`
/// 现在不需要（sqflite 直查足够快），`PlaylistRepository` 已被并入 `PlaylistService`，两者
/// 共享同一份 sqflite 真理。
///
/// 这个类现在是一层薄转发，把公开方法调用直接派发到 service 实例，避免改 UI 端每个 import。
class PlaylistManager {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;
  PlaylistManager._internal();

  late PlaylistService _service;
  bool _initialized = false;

  /// 由 `ServiceLocator` 在启动时调用一次。
  Future<void> initialize({PlaylistService? service}) async {
    if (_initialized) return;
    _service = service ?? PlaylistService();
    await _service.initialize();
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'PlaylistManager has not been initialized. '
        'Call PlaylistManager().initialize() before using.',
      );
    }
  }

  // ==================== 歌单基础操作 ====================

  ValueListenable<List<Playlist>> watchUserPlaylists() {
    _ensureInitialized();
    return _service.watchUserPlaylists();
  }

  List<Playlist> get userPlaylists {
    _ensureInitialized();
    return _service.userPlaylistsSnapshot;
  }

  Playlist? getPlaylistInfo(String playlistId) {
    _ensureInitialized();
    return _service.getPlaylistInfo(playlistId);
  }

  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    _ensureInitialized();
    return _service.getPlaylistDetail(playlistId);
  }

  Future<Playlist?> getSystemPlaylistDetail(String playlistId) async {
    _ensureInitialized();
    return _service.getSystemPlaylistDetail(playlistId);
  }

  Future<Playlist> createPlaylist(
    String name, {
    String? description,
    List<String> tagIds = const [],
    PlaylistSource source = PlaylistSource.user,
  }) async {
    _ensureInitialized();
    return _service.createPlaylist(
      name: name,
      description: description,
      tagIds: tagIds,
      source: source,
    );
  }

  Future<void> deletePlaylist(String playlistId) async {
    _ensureInitialized();
    return _service.deletePlaylist(playlistId);
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    _ensureInitialized();
    return _service.renamePlaylist(playlistId, newName);
  }

  Future<void> updatePlaylistDescription(
    String playlistId,
    String? description,
  ) async {
    _ensureInitialized();
    return _service.updatePlaylistDescription(playlistId, description);
  }

  Future<void> addTagToPlaylist(String playlistId, String tagId) async {
    _ensureInitialized();
    return _service.addTagToPlaylist(playlistId, tagId);
  }

  Future<void> removeTagFromPlaylist(String playlistId, String tagId) async {
    _ensureInitialized();
    return _service.removeTagFromPlaylist(playlistId, tagId);
  }

  List<Playlist> filterPlaylistsByTag(String tagId) {
    _ensureInitialized();
    return _service.filterPlaylistsByTag(tagId);
  }

  bool isSystemPlaylist(String playlistId) {
    _ensureInitialized();
    return _service.isSystemPlaylist(playlistId);
  }

  List<Playlist> get systemPlaylists {
    _ensureInitialized();
    return _service.systemPlaylists;
  }

  // ==================== 歌曲操作 ====================

  Future<bool> addSongsToPlaylist(String playlistId, List<Music> songs) async {
    _ensureInitialized();
    return _service.addSongsToPlaylist(playlistId, songs);
  }

  Future<bool> addSongToPlaylist(String playlistId, Music music) async {
    _ensureInitialized();
    return _service.addSongToUserPlaylist(playlistId, music);
  }

  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<Music> songs,
  ) async {
    _ensureInitialized();
    return _service.removeSongsFromPlaylist(playlistId, songs);
  }

  Future<List<Music>> loadPlaylistSongs(String playlistId) async {
    _ensureInitialized();
    return _service.loadPlaylistSongs(playlistId);
  }

  Future<void> updatePlaylistCover(String playlistId, List<Music> songs) async {
    _ensureInitialized();
    return _service.updatePlaylistCover(playlistId, songs);
  }

  // ==================== 收藏操作 ====================

  ValueListenable<List<Music>> watchFavorites() {
    _ensureInitialized();
    return _service.watchFavorites();
  }

  List<Music> get favorites {
    _ensureInitialized();
    return _service.favoritesSnapshot;
  }

  Future<bool> toggleFavorite(Music music) async {
    _ensureInitialized();
    return _service.toggleFavorite(music);
  }

  Future<void> addToFavorites(Music music) async {
    _ensureInitialized();
    return _service.addToFavorites(music);
  }

  Future<void> removeFromFavorites(Music music) async {
    _ensureInitialized();
    return _service.removeFromFavorites(music);
  }

  bool isFavorite(Music music) {
    _ensureInitialized();
    return _service.isFavorite(music);
  }

  // ==================== 播放历史操作 ====================

  ValueListenable<List<Music>> watchPlayHistory() {
    _ensureInitialized();
    return _service.watchPlayHistory();
  }

  List<Music> get playHistory {
    _ensureInitialized();
    return _service.playHistorySnapshot;
  }

  Future<void> addToHistory(Music music) async {
    _ensureInitialized();
    return _service.addToPlayHistory(music);
  }

  Future<void> clearHistory() async {
    _ensureInitialized();
    return _service.clearPlayHistory();
  }

  // ==================== 标签操作 ====================

  ValueListenable<List<PlaylistTag>> watchTags() {
    _ensureInitialized();
    return _service.watchTags();
  }

  Map<TagCategory, List<PlaylistTag>> getTagsByCategory() {
    _ensureInitialized();
    return _service.getTagsByCategory();
  }

  Future<PlaylistTag> createCustomTag({
    required String name,
    required String nameCn,
    int colorValue = 0xFF636E72,
  }) async {
    _ensureInitialized();
    return _service.createCustomTag(
      name: name,
      nameCn: nameCn,
      colorValue: colorValue,
    );
  }

  // ==================== 数据运维 ====================

  Future<Map<String, String?>> exportForBackup() async {
    _ensureInitialized();
    return _service.exportForBackup();
  }

  Future<void> importFromBackup(Map<String, dynamic> data) async {
    _ensureInitialized();
    return _service.importFromBackup(data);
  }

  Future<void> clearAllUserData() async {
    _ensureInitialized();
    return _service.clearAllUserData();
  }

  int get historyCount {
    _ensureInitialized();
    return _service.historyCount;
  }

  int get favoritesCount {
    _ensureInitialized();
    return _service.favoritesCount;
  }

  int get userPlaylistsCount {
    _ensureInitialized();
    return _service.userPlaylistsCount;
  }

  // ==================== 向后兼容 ====================

  Future<void> init() async {
    await initialize();
  }

  List<Playlist> getAllPlaylists() {
    _ensureInitialized();
    return _service.userPlaylistsSnapshot;
  }

  Future<List<Music>> getPlaylistSongs(String playlistId) async {
    _ensureInitialized();
    return _service
        .getPlaylistDetail(playlistId)
        .then((d) => d?.songs ?? <Music>[]);
  }
}
