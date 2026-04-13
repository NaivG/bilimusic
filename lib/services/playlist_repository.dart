import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/models/playlist.dart';

/// 歌单数据仓库
/// 职责：
/// - 管理用户歌单、收藏列表、播放历史的持久化
/// - 提供分离存储（歌单元数据 + 歌曲列表）
/// - 提供响应式数据流
class PlaylistRepository {
  SharedPreferences? _prefs;

  // ============ 核心状态 ============
  final ValueNotifier<List<Music>> _playHistory = ValueNotifier([]);
  final ValueNotifier<List<Music>> _favorites = ValueNotifier([]);
  final ValueNotifier<List<Playlist>> _userPlaylists = ValueNotifier([]);
  final ValueNotifier<List<PlaylistTag>> _allTags = ValueNotifier([]);

  static const int _maxHistorySize = 100;
  static const int _maxFavoritesSize = 500;

  PlaylistRepository();

  // ============ 初始化 ============

  /// 初始化仓库
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAllData();
    _initializeDefaultTags();
  }

  /// 初始化默认标签
  void _initializeDefaultTags() {
    _allTags.value = DefaultPlaylistTags.allTags;
  }

  /// 加载所有数据
  Future<void> _loadAllData() async {
    await _loadPlayHistory();
    await _loadFavorites();
    await _loadUserPlaylists();
    await _loadCustomTags();
  }

  // ============ 播放历史 ============

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
                  debugPrint('Failed to parse music in history: $e');
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

  /// 添加到播放历史
  Future<void> addToHistory(Music music) async {
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
  Future<void> clearHistory() async {
    _playHistory.value = [];
    await _savePlayHistory();
  }

  // ============ 收藏列表 ============

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
                  debugPrint('Failed to parse music in favorites: $e');
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

  /// 添加到收藏
  Future<void> addToFavorites(Music music) async {
    final index = _findMusicIndex(_favorites.value, music);
    if (index == -1) {
      final favoritedMusic = music.copyWith(isFavorite: true);
      _favorites.value = [..._favorites.value, favoritedMusic];
      await _saveFavorites();
    }
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(Music music) async {
    final index = _findMusicIndex(_favorites.value, music);
    if (index != -1) {
      final newFavorites = List<Music>.from(_favorites.value);
      newFavorites.removeAt(index);
      _favorites.value = newFavorites;
      await _saveFavorites();
    }
  }

  /// 检查是否已收藏
  bool isFavorite(Music music) {
    return _findMusicIndex(_favorites.value, music) != -1;
  }

  // ============ 用户歌单 ============

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

  /// 创建新歌单
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

  /// 删除歌单
  Future<void> deletePlaylist(String playlistId) async {
    _userPlaylists.value = _userPlaylists.value
        .where((p) => p.id != playlistId)
        .toList();
    await _saveUserPlaylists();
    // 清除歌曲数据
    await _savePlaylistSongs(playlistId, []);
  }

  /// 更新歌单名称
  Future<void> updatePlaylistName(String playlistId, String newName) async {
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

  /// 添加标签到歌单
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

  // ============ 歌单歌曲（分离存储） ============

  /// 加载歌单歌曲
  Future<List<Music>> loadPlaylistSongs(String playlistId) async {
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

  /// 添加歌曲到歌单
  Future<bool> addSongsToPlaylist(
    String playlistId,
    List<Music> newSongs,
  ) async {
    final songs = await loadPlaylistSongs(playlistId);
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
      // 添加歌曲后自动更新封面（使用第一首歌的封面）
      await _updatePlaylistCoverInternal(playlistId, songs);
      return true;
    }
    return false;
  }

  /// 更新歌单封面（使用第一首歌的封面）
  Future<void> _updatePlaylistCoverInternal(
    String playlistId,
    List<Music> songs,
  ) async {
    // 只为用户歌单更新封面，不更新系统歌单
    if (isSystemPlaylist(playlistId)) return;

    // 如果歌曲列表为空，不更新封面
    if (songs.isEmpty) return;

    // 使用第一首歌的封面作为歌单封面
    final coverUrl = songs.first.safeCoverUrl;
    if (coverUrl.isEmpty) return;

    final index = _userPlaylists.value.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _userPlaylists.value[index];
      // 只有当封面不同时才更新
      if (playlist.coverUrl != coverUrl) {
        _userPlaylists.value = [
          ..._userPlaylists.value.sublist(0, index),
          playlist.copyWith(coverUrl: coverUrl, updatedAt: DateTime.now()),
          ..._userPlaylists.value.sublist(index + 1),
        ];
        await _saveUserPlaylists();
      }
    }
  }

  /// 更新歌单封面（公共方法）
  /// 当歌单没有封面时，使用第一首歌的封面
  Future<void> updatePlaylistCover(String playlistId, List<Music> songs) async {
    await _updatePlaylistCoverInternal(playlistId, songs);
  }

  /// 从歌单移除歌曲
  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<Music> songsToRemove,
  ) async {
    final songs = await loadPlaylistSongs(playlistId);

    songs.removeWhere((s) {
      return songsToRemove.any(
        (toRemove) => s.id == toRemove.id && s.cid == toRemove.cid,
      );
    });

    await _savePlaylistSongs(playlistId, songs);
    await _updatePlaylistSongCount(playlistId, songs.length);
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

  // ============ 标签 ============

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

  // ============ Getters ============

  /// 监听播放历史
  ValueListenable<List<Music>> watchPlayHistory() => _playHistory;

  /// 监听收藏列表
  ValueListenable<List<Music>> watchFavorites() => _favorites;

  /// 监听用户歌单列表
  ValueListenable<List<Playlist>> watchUserPlaylists() => _userPlaylists;

  /// 监听所有标签
  ValueListenable<List<PlaylistTag>> watchTags() => _allTags;

  /// 获取播放历史
  List<Music> get playHistory => _playHistory.value;

  /// 获取收藏列表
  List<Music> get favorites => _favorites.value;

  /// 获取用户歌单
  List<Playlist> get userPlaylists => _userPlaylists.value;

  /// 获取歌单元数据
  Playlist? getPlaylistInfo(String playlistId) {
    try {
      return _userPlaylists.value.firstWhere((p) => p.id == playlistId);
    } catch (_) {
      return null;
    }
  }

  /// 获取系统歌单详情
  Playlist? getSystemPlaylistDetail(String playlistId) {
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
    return null;
  }

  /// 检查是否为系统歌单
  bool isSystemPlaylist(String playlistId) {
    return DefaultPlaylists.getById(playlistId) != null;
  }

  /// 根据标签筛选歌单
  List<Playlist> filterPlaylistsByTag(String tagId) {
    return _userPlaylists.value.where((p) => p.tagIds.contains(tagId)).toList();
  }

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

  // ============ 工具方法 ============

  /// 在列表中查找音乐索引
  int _findMusicIndex(List<Music> list, Music music) {
    return list.indexWhere((m) => m.id == music.id && m.cid == music.cid);
  }

  /// 释放资源
  Future<void> dispose() async {
    await _savePlayHistory();
    await _saveFavorites();
    await _saveUserPlaylists();
  }
}
