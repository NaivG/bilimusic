import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/models/playlist.dart';

import 'package:bilimusic/managers/player_manager.dart';

/// 播放列表管理服务
/// 管理播放列表、播放历史、收藏列表的增删改查和持久化
class PlaylistService {
  // ============ 核心状态 ============
  final ValueNotifier<List<Music>> _currentPlaylist = ValueNotifier([]);
  final ValueNotifier<int?> _currentIndex = ValueNotifier(null);
  final ValueNotifier<List<Music>> _playHistory = ValueNotifier([]);
  final ValueNotifier<List<Music>> _favorites = ValueNotifier([]);

  // ============ 歌单管理状态 ============
  final ValueNotifier<List<Playlist>> _userPlaylists = ValueNotifier([]);
  final ValueNotifier<List<PlaylistTag>> _allTags = ValueNotifier([]);
  final ValueNotifier<Playlist?> _currentPlaylistDetail = ValueNotifier(null);

  SharedPreferences? _prefs;
  static const int _maxHistorySize = 100;
  static const int _maxFavoritesSize = 500;

  PlaylistService();

  /// 初始化服务
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAllData();
    // 初始化默认标签
    _initializeDefaultTags();
  }

  /// 初始化默认标签
  void _initializeDefaultTags() {
    _allTags.value = DefaultPlaylistTags.allTags;
  }

  /// 加载所有数据
  Future<void> _loadAllData() async {
    await _loadPlaylist();
    await _loadPlayHistory();
    await _loadFavorites();
    await _loadUserPlaylists();
  }

  // ============ 当前播放列表操作 ============

  /// 加载播放列表
  Future<void> _loadPlaylist() async {
    try {
      if (_prefs == null) return;
      final playlistJson = _prefs!.getString('playlist');
      if (playlistJson != null && playlistJson.isNotEmpty) {
        final decoded = jsonDecode(playlistJson);
        if (decoded is List<dynamic>) {
          final playlist = decoded
              .map((json) {
                try {
                  return Music.fromJson(json);
                } catch (e) {
                  debugPrint('Failed to parse music item: $e');
                  return null;
                }
              })
              .where((music) => music != null)
              .cast<Music>()
              .toList();

          _currentPlaylist.value = playlist;
        }
      }
    } catch (e) {
      debugPrint('Failed to load playlist: $e');
    }
  }

  /// 保存播放列表
  Future<void> _savePlaylist() async {
    try {
      if (_prefs == null) return;
      final playlistJson = jsonEncode(
        _currentPlaylist.value.map((music) => music.toJson()).toList(),
      );
      await _prefs!.setString('playlist', playlistJson);
    } catch (e) {
      debugPrint('Failed to save playlist: $e');
    }
  }

  /// 加载播放历史
  Future<void> _loadPlayHistory() async {
    try {
      if (_prefs == null) return;
      final historyJson = _prefs!.getString('play_history');
      if (historyJson != null && historyJson.isNotEmpty) {
        final decoded = jsonDecode(historyJson);
        if (decoded is List<dynamic>) {
          final history = decoded
              .map((json) {
                try {
                  return Music.fromJson(json);
                } catch (e) {
                  debugPrint('Failed to parse music item in history: $e');
                  return null;
                }
              })
              .where((music) => music != null)
              .cast<Music>()
              .toList();

          _playHistory.value = history;
        }
      }
    } catch (e) {
      debugPrint('Failed to load play history: $e');
    }
  }

  /// 保存播放历史
  Future<void> _savePlayHistory() async {
    try {
      if (_prefs == null) return;
      final historyJson = jsonEncode(
        _playHistory.value.map((music) => music.toJson()).toList(),
      );
      await _prefs!.setString('play_history', historyJson);
    } catch (e) {
      debugPrint('Failed to save play history: $e');
    }
  }

  /// 加载收藏列表
  Future<void> _loadFavorites() async {
    try {
      if (_prefs == null) return;
      final favoritesJson = _prefs!.getString('favorites');
      if (favoritesJson != null && favoritesJson.isNotEmpty) {
        final decoded = jsonDecode(favoritesJson);
        if (decoded is List<dynamic>) {
          final favorites = decoded
              .map((json) {
                try {
                  return Music.fromJson(json);
                } catch (e) {
                  debugPrint('Failed to parse music item in favorites: $e');
                  return null;
                }
              })
              .where((music) => music != null)
              .cast<Music>()
              .toList();

          _favorites.value = favorites;
        }
      }
    } catch (e) {
      debugPrint('Failed to load favorites: $e');
    }
  }

  /// 保存收藏列表
  Future<void> _saveFavorites() async {
    try {
      if (_prefs == null) return;
      final favoritesJson = jsonEncode(
        _favorites.value.map((music) => music.toJson()).toList(),
      );
      await _prefs!.setString('favorites', favoritesJson);
    } catch (e) {
      debugPrint('Failed to save favorites: $e');
    }
  }

  // ============ 用户歌单操作 ============

  /// 加载用户歌单
  Future<void> _loadUserPlaylists() async {
    try {
      if (_prefs == null) return;
      final playlistsJson = _prefs!.getString('user_playlists_enhanced');
      if (playlistsJson != null && playlistsJson.isNotEmpty) {
        final decoded = jsonDecode(playlistsJson);
        if (decoded is List<dynamic>) {
          final playlists = decoded
              .map((json) {
                try {
                  return Playlist.fromJson(json);
                } catch (e) {
                  debugPrint('Failed to parse playlist: $e');
                  return null;
                }
              })
              .where((p) => p != null)
              .cast<Playlist>()
              .toList();

          _userPlaylists.value = playlists;
        }
      }
    } catch (e) {
      debugPrint('Failed to load user playlists: $e');
    }
  }

  /// 保存用户歌单
  Future<void> _saveUserPlaylists() async {
    try {
      if (_prefs == null) return;
      final playlistsJson = jsonEncode(
        _userPlaylists.value.map((p) => p.toJson()).toList(),
      );
      await _prefs!.setString('user_playlists_enhanced', playlistsJson);
    } catch (e) {
      debugPrint('Failed to save user playlists: $e');
    }
  }

  // ============ Getters ============

  /// 获取当前播放列表
  ValueListenable<List<Music>> get currentPlaylist => _currentPlaylist;

  /// 获取当前播放索引
  ValueListenable<int?> get currentIndex => _currentIndex;

  /// 获取播放历史
  ValueListenable<List<Music>> get playHistory => _playHistory;

  /// 获取收藏列表
  ValueListenable<List<Music>> get favorites => _favorites;

  /// 获取用户歌单列表
  ValueListenable<List<Playlist>> get userPlaylists => _userPlaylists;

  /// 获取所有可用标签
  ValueListenable<List<PlaylistTag>> get allTags => _allTags;

  /// 获取当前歌单详情
  ValueListenable<Playlist?> get currentPlaylistDetail =>
      _currentPlaylistDetail;

  /// 获取当前播放的音乐
  Music? get currentMusic {
    final index = _currentIndex.value;
    if (index != null && index >= 0 && index < _currentPlaylist.value.length) {
      return _currentPlaylist.value[index];
    }
    return null;
  }

  /// 获取播放列表长度
  int get playlistLength => _currentPlaylist.value.length;

  /// 获取当前播放索引（同步）
  int? get currentIndexSync => _currentIndex.value;

  // ============ 当前播放列表操作 ============

  /// 设置当前播放索引
  void setCurrentIndex(int index) {
    if (index >= 0 && index < _currentPlaylist.value.length) {
      _currentIndex.value = index;
    } else {
      _currentIndex.value = null;
    }
  }

  /// 添加音乐到播放列表
  Future<void> addToPlaylist(Music music) async {
    final existingIndex = _findMusicIndex(_currentPlaylist.value, music);
    if (existingIndex == -1) {
      _currentPlaylist.value = [..._currentPlaylist.value, music];
      await _savePlaylist();
    }
  }

  /// 批量添加音乐到播放列表
  Future<void> addAllToPlaylist(List<Music> musics) async {
    final newMusics = musics
        .where((music) => _findMusicIndex(_currentPlaylist.value, music) == -1)
        .toList();

    if (newMusics.isNotEmpty) {
      _currentPlaylist.value = [..._currentPlaylist.value, ...newMusics];
      await _savePlaylist();
    }
  }

  /// 从播放列表移除音乐
  Future<void> removeFromPlaylist(Music music) async {
    final index = _findMusicIndex(_currentPlaylist.value, music);
    if (index != -1) {
      final newPlaylist = List<Music>.from(_currentPlaylist.value);
      newPlaylist.removeAt(index);
      _currentPlaylist.value = newPlaylist;

      // 调整当前索引
      final currentIdx = _currentIndex.value;
      if (currentIdx != null) {
        if (index == currentIdx) {
          if (newPlaylist.isNotEmpty) {
            _currentIndex.value = index < newPlaylist.length
                ? index
                : newPlaylist.length - 1;
          } else {
            _currentIndex.value = null;
          }
        } else if (index < currentIdx) {
          _currentIndex.value = currentIdx - 1;
        }
      }

      await _savePlaylist();
    }
  }

  /// 清空播放列表
  Future<void> clearPlaylist() async {
    _currentPlaylist.value = [];
    _currentIndex.value = null;
    await _savePlaylist();
  }

  /// 在指定位置插入音乐
  Future<void> insertToPlaylist(Music music, int index) async {
    final newPlaylist = List<Music>.from(_currentPlaylist.value);
    if (index >= 0 && index <= newPlaylist.length) {
      newPlaylist.insert(index, music);
      _currentPlaylist.value = newPlaylist;
      await _savePlaylist();
    }
  }

  /// 移动音乐到指定位置
  Future<void> moveInPlaylist(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex) return;
    final currentIdx = _currentIndex.value;
    final newPlaylist = List<Music>.from(_currentPlaylist.value);
    if (fromIndex >= 0 &&
        fromIndex < newPlaylist.length &&
        toIndex >= 0 &&
        toIndex < newPlaylist.length) {
      final music = newPlaylist.removeAt(fromIndex);
      newPlaylist.insert(toIndex, music);
      _currentPlaylist.value = newPlaylist;

      // 同步更新 currentIndex
      if (currentIdx != null) {
        if (fromIndex == currentIdx) {
          // 移动的是当前播放的歌曲，更新索引为新位置
          _currentIndex.value = toIndex;
        } else if (fromIndex < currentIdx && toIndex >= currentIdx) {
          // 从前移动到当前索引之后，currentIndex 减 1
          _currentIndex.value = currentIdx - 1;
        } else if (fromIndex > currentIdx && toIndex <= currentIdx) {
          // 从后移动到当前索引之前，currentIndex 加 1
          _currentIndex.value = currentIdx + 1;
        }
        // 其他情况 currentIndex 不变
      }

      await _savePlaylist();
    }
  }

  // ============ 播放历史操作 ============

  /// 添加音乐到播放历史
  Future<void> addToPlayHistory(Music music) async {
    final index = _findMusicIndex(_playHistory.value, music);
    final newHistory = List<Music>.from(_playHistory.value);

    if (index != -1) {
      newHistory.removeAt(index);
      newHistory.insert(0, music);
    } else {
      newHistory.insert(0, music);
      if (newHistory.length > _maxHistorySize) {
        newHistory.removeRange(_maxHistorySize, newHistory.length);
      }
    }

    _playHistory.value = newHistory;
    await _savePlayHistory();
  }

  /// 清空播放历史
  Future<void> clearPlayHistory() async {
    _playHistory.value = [];
    await _savePlayHistory();
  }

  // ============ 收藏操作 ============

  /// 添加音乐到收藏
  Future<void> addToFavorites(Music music) async {
    final index = _findMusicIndex(_favorites.value, music);
    if (index == -1) {
      final favoritedMusic = music.copyWith(isFavorite: true);
      _favorites.value = [..._favorites.value, favoritedMusic];
      await _saveFavorites();

      _updateFavoriteStatusInLists(music, true);
    }
  }

  /// 从收藏移除音乐
  Future<void> removeFromFavorites(Music music) async {
    final index = _findMusicIndex(_favorites.value, music);
    if (index != -1) {
      final newFavorites = List<Music>.from(_favorites.value);
      newFavorites.removeAt(index);
      _favorites.value = newFavorites;
      await _saveFavorites();

      _updateFavoriteStatusInLists(music, false);
    }
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(Music music) async {
    if (isFavorite(music)) {
      await removeFromFavorites(music);
      return false;
    } else {
      await addToFavorites(music);
      return true;
    }
  }

  /// 检查音乐是否已收藏
  bool isFavorite(Music music) {
    return _findMusicIndex(_favorites.value, music) != -1;
  }

  /// 更新列表中的收藏状态
  void _updateFavoriteStatusInLists(Music music, bool isFavorite) {
    final playlistIndex = _findMusicIndex(_currentPlaylist.value, music);
    if (playlistIndex != -1) {
      final newPlaylist = List<Music>.from(_currentPlaylist.value);
      newPlaylist[playlistIndex] = newPlaylist[playlistIndex].copyWith(
        isFavorite: isFavorite,
      );
      _currentPlaylist.value = newPlaylist;
      _savePlaylist();
    }

    final historyIndex = _findMusicIndex(_playHistory.value, music);
    if (historyIndex != -1) {
      final newHistory = List<Music>.from(_playHistory.value);
      newHistory[historyIndex] = newHistory[historyIndex].copyWith(
        isFavorite: isFavorite,
      );
      _playHistory.value = newHistory;
      _savePlayHistory();
    }
  }

  // ============ 用户歌单操作 (CRUD) ============

  /// 创建新的用户歌单
  Future<Playlist> createPlaylist({
    required String name,
    String? description,
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'playlist_${now.millisecondsSinceEpoch}',
      name: name,
      description: description,
      tagIds: tagIds,
      source: PlaylistSource.user,
      createdAt: now,
      updatedAt: now,
    );

    _userPlaylists.value = [..._userPlaylists.value, playlist];
    await _saveUserPlaylists();

    return playlist;
  }

  /// 删除用户歌单
  Future<void> deletePlaylist(String playlistId) async {
    _userPlaylists.value = _userPlaylists.value
        .where((p) => p.id != playlistId)
        .toList();
    await _saveUserPlaylists();
    await _savePlaylistSongs(playlistId, []);
  }

  /// 重命名歌单
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _userPlaylists.value[index];
      _userPlaylists.value = [
        ..._userPlaylists.value.sublist(0, index),
        playlist.copyWith(name: newName, updatedAt: DateTime.now()),
        ..._userPlaylists.value.sublist(index + 1),
      ];
      await _saveUserPlaylists();
    }
  }

  /// 更新歌单描述
  Future<void> updatePlaylistDescription(
    String playlistId,
    String? description,
  ) async {
    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _userPlaylists.value[index];
      _userPlaylists.value = [
        ..._userPlaylists.value.sublist(0, index),
        playlist.copyWith(description: description, updatedAt: DateTime.now()),
        ..._userPlaylists.value.sublist(index + 1),
      ];
      await _saveUserPlaylists();
    }
  }

  /// 为歌单添加标签
  Future<void> addTagToPlaylist(String playlistId, String tagId) async {
    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _userPlaylists.value[index];
      if (!playlist.tagIds.contains(tagId)) {
        _userPlaylists.value = [
          ..._userPlaylists.value.sublist(0, index),
          playlist.copyWith(
            tagIds: [...playlist.tagIds, tagId],
            updatedAt: DateTime.now(),
          ),
          ..._userPlaylists.value.sublist(index + 1),
        ];
        await _saveUserPlaylists();
      }
    }
  }

  /// 从歌单移除标签
  Future<void> removeTagFromPlaylist(String playlistId, String tagId) async {
    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _userPlaylists.value[index];
      _userPlaylists.value = [
        ..._userPlaylists.value.sublist(0, index),
        playlist.copyWith(
          tagIds: playlist.tagIds.where((id) => id != tagId).toList(),
          updatedAt: DateTime.now(),
        ),
        ..._userPlaylists.value.sublist(index + 1),
      ];
      await _saveUserPlaylists();
    }
  }

  /// 获取歌单详情（包含歌曲列表）
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    // 检查是否为系统歌单
    final defaultPlaylist = DefaultPlaylists.getById(playlistId);
    if (defaultPlaylist != null) {
      List<Music> songs;
      switch (playlistId) {
        case 'favorites':
          songs = _favorites.value;
          break;
        case 'history':
          songs = _playHistory.value;
          break;
        default:
          songs = [];
      }
      return defaultPlaylist.copyWith(songs: songs, songCount: songs.length);
    }

    // 用户歌单
    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index == -1) return null;

    final playlist = _userPlaylists.value[index];
    final songs = await _loadPlaylistSongs(playlistId);
    return playlist.copyWith(songs: songs);
  }

  /// 设置当前查看的歌单
  void setCurrentPlaylistDetail(Playlist? playlist) {
    _currentPlaylistDetail.value = playlist;
  }

  // ============ 歌单歌曲操作 ============

  /// 加载歌单歌曲
  Future<List<Music>> _loadPlaylistSongs(String playlistId) async {
    try {
      if (_prefs == null) return [];
      final songsJson = _prefs!.getString('playlist_songs_$playlistId');
      if (songsJson != null && songsJson.isNotEmpty) {
        final decoded = jsonDecode(songsJson);
        if (decoded is List<dynamic>) {
          return decoded
              .map((json) {
                try {
                  return Music.fromJson(json);
                } catch (e) {
                  return null;
                }
              })
              .where((m) => m != null)
              .cast<Music>()
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Failed to load playlist songs: $e');
    }
    return [];
  }

  /// 保存歌单歌曲
  Future<void> _savePlaylistSongs(String playlistId, List<Music> songs) async {
    try {
      if (_prefs == null) return;
      final songsJson = jsonEncode(songs.map((s) => s.toJson()).toList());
      await _prefs!.setString('playlist_songs_$playlistId', songsJson);
    } catch (e) {
      debugPrint('Failed to save playlist songs: $e');
    }
  }

  /// 向歌单添加歌曲
  Future<void> addSongToUserPlaylist(String playlistId, Music song) async {
    final songs = await _loadPlaylistSongs(playlistId);

    // 检查是否已存在
    final exists = songs.any((s) => s.id == song.id && s.cid == song.cid);

    if (!exists) {
      songs.add(song);
      await _savePlaylistSongs(playlistId, songs);
      await _updatePlaylistSongCount(playlistId, songs.length);
    }
  }

  /// 从歌单移除歌曲
  Future<void> removeSongFromUserPlaylist(String playlistId, Music song) async {
    final songs = await _loadPlaylistSongs(playlistId);

    songs.removeWhere((s) => s.id == song.id && s.cid == song.cid);

    await _savePlaylistSongs(playlistId, songs);
    await _updatePlaylistSongCount(playlistId, songs.length);
  }

  /// 批量添加歌曲到歌单
  Future<void> addSongsToUserPlaylist(
    String playlistId,
    List<Music> newSongs,
  ) async {
    final songs = await _loadPlaylistSongs(playlistId);
    final existingIds = songs.map((s) => '${s.id}_${s.cid}').toSet();

    int addedCount = 0;
    for (final song in newSongs) {
      final songKey = '${song.id}_${song.cid}';
      if (!existingIds.contains(songKey)) {
        songs.add(song);
        addedCount++;
      }
    }

    if (addedCount > 0) {
      await _savePlaylistSongs(playlistId, songs);
      await _updatePlaylistSongCount(playlistId, songs.length);
    }
  }

  /// 更新歌单歌曲数量
  Future<void> _updatePlaylistSongCount(String playlistId, int count) async {
    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _userPlaylists.value[index];
      _userPlaylists.value = [
        ..._userPlaylists.value.sublist(0, index),
        playlist.copyWith(songCount: count, updatedAt: DateTime.now()),
        ..._userPlaylists.value.sublist(index + 1),
      ];
      await _saveUserPlaylists();
    }
  }

  // ============ 标签操作 ============

  /// 获取所有标签（按分类分组）
  Map<TagCategory, List<PlaylistTag>> getTagsByCategory() {
    final tags = _allTags.value;
    return {
      TagCategory.genre: tags
          .where((t) => t.category == TagCategory.genre)
          .toList(),
      TagCategory.scenario: tags
          .where((t) => t.category == TagCategory.scenario)
          .toList(),
      TagCategory.mood: tags
          .where((t) => t.category == TagCategory.mood)
          .toList(),
      TagCategory.custom: tags
          .where((t) => t.category == TagCategory.custom)
          .toList(),
    };
  }

  /// 根据标签ID获取标签
  PlaylistTag? getTagById(String tagId) {
    try {
      return _allTags.value.firstWhere((t) => t.id == tagId);
    } catch (_) {
      return null;
    }
  }

  /// 根据标签筛选歌单
  List<Playlist> filterPlaylistsByTag(String tagId) {
    return _userPlaylists.value.where((p) => p.tagIds.contains(tagId)).toList();
  }

  /// 创建自定义标签
  Future<PlaylistTag> createCustomTag({
    required String name,
    required String nameCn,
    int colorValue = 0xFF636E72,
  }) async {
    final now = DateTime.now();
    final tag = PlaylistTag(
      id: 'custom_${now.millisecondsSinceEpoch}',
      name: name,
      nameCn: nameCn,
      category: TagCategory.custom,
      colorValue: colorValue,
      isSystem: false,
    );

    _allTags.value = [..._allTags.value, tag];
    await _saveCustomTags();

    return tag;
  }

  /// 保存自定义标签
  Future<void> _saveCustomTags() async {
    try {
      if (_prefs == null) return;
      final customTags = _allTags.value
          .where((t) => !t.isSystem)
          .map((t) => t.toJson())
          .toList();
      final tagsJson = jsonEncode(customTags);
      await _prefs!.setString('custom_tags', tagsJson);
    } catch (e) {
      debugPrint('Failed to save custom tags: $e');
    }
  }

  /// 加载自定义标签
  Future<void> _loadCustomTags() async {
    try {
      if (_prefs == null) return;
      final tagsJson = _prefs!.getString('custom_tags');
      if (tagsJson != null && tagsJson.isNotEmpty) {
        final decoded = jsonDecode(tagsJson);
        if (decoded is List<dynamic>) {
          final customTags = decoded
              .map((json) {
                try {
                  return PlaylistTag.fromJson(json);
                } catch (e) {
                  return null;
                }
              })
              .where((t) => t != null)
              .cast<PlaylistTag>()
              .toList();

          _allTags.value = [...DefaultPlaylistTags.allTags, ...customTags];
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom tags: $e');
    }
  }

  // ============ 播放控制辅助方法 ============

  /// 获取下一首索引（根据播放模式）
  int? getNextIndex(PlayMode playMode, {Random? random}) {
    final currentIdx = _currentIndex.value;
    if (currentIdx == null || _currentPlaylist.value.isEmpty) return null;

    switch (playMode) {
      case PlayMode.sequential:
        return (currentIdx + 1) % _currentPlaylist.value.length;
      case PlayMode.loop:
        return currentIdx;
      case PlayMode.shuffle:
        final rng = random ?? Random();
        var newIndex = rng.nextInt(_currentPlaylist.value.length);
        while (newIndex == currentIdx && _currentPlaylist.value.length > 1) {
          newIndex = rng.nextInt(_currentPlaylist.value.length);
        }
        return newIndex;
    }
  }

  /// 获取上一首索引（根据播放模式）
  int? getPreviousIndex(PlayMode playMode, {Random? random}) {
    final currentIdx = _currentIndex.value;
    if (currentIdx == null || _currentPlaylist.value.isEmpty) return null;

    switch (playMode) {
      case PlayMode.sequential:
        return (currentIdx - 1 + _currentPlaylist.value.length) %
            _currentPlaylist.value.length;
      case PlayMode.loop:
        return currentIdx;
      case PlayMode.shuffle:
        final rng = random ?? Random();
        var newIndex = rng.nextInt(_currentPlaylist.value.length);
        while (newIndex == currentIdx && _currentPlaylist.value.length > 1) {
          newIndex = rng.nextInt(_currentPlaylist.value.length);
        }
        return newIndex;
    }
  }

  // ============ 工具方法 ============

  /// 在列表中查找音乐索引
  int _findMusicIndex(List<Music> list, Music music) {
    return list.indexWhere((m) => m.id == music.id && m.cid == music.cid);
  }

  /// 释放资源
  Future<void> dispose() async {
    await _savePlaylist();
    await _savePlayHistory();
    await _saveFavorites();
    await _saveUserPlaylists();
  }
}
