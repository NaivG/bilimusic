import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:bilimusic/core/database.dart';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';

/// 唯一一份播放列表数据层。
///
/// 之前由 `playlist_service.dart` 和 `playlist_repository.dart` 各自维护一份 SharedPreferences
/// 镜像，两边互不感知、可能漂移。合并后这里同时承担：
///
/// - 当前播放队列（被 PlayerCoordinator 写入）
/// - 收藏列表 + 播放历史（被 UI + 协调器写入）
/// - 用户歌单元数据 + 歌曲列表（被 PlaylistManager / FavSyncManager 写入）
/// - 自定义标签
///
/// 底层是 `AppDatabase`（`playlist.db`）。每次写操作落盘后立刻重新加载该集合的内存镜像
/// 并触发 `ValueNotifier`，所以监听者（PlayerCoordinator 的 listeners / UI 重建）拿到
/// 的永远是数据库的当前状态，没有第二个持有者会漂移。
class PlaylistService {
  static const int _maxHistorySize = 100;

  final ValueNotifier<List<Music>> _currentPlaylist = ValueNotifier([]);
  final ValueNotifier<int?> _currentIndex = ValueNotifier(null);
  final ValueNotifier<List<Music>> _playHistory = ValueNotifier([]);
  final ValueNotifier<List<Music>> _favorites = ValueNotifier([]);
  final ValueNotifier<List<Playlist>> _userPlaylists = ValueNotifier([]);
  final ValueNotifier<List<PlaylistTag>> _allTags = ValueNotifier([]);
  final ValueNotifier<Playlist?> _currentPlaylistDetail = ValueNotifier(null);

  Database? _db;
  List<PlaylistTag> _defaultTagsCache = const [];

  PlaylistService();

  Database get _dbChecked {
    final db = _db;
    if (db == null) {
      throw StateError('PlaylistService not initialized');
    }
    return db;
  }

  Future<void> initialize() async {
    _db = await AppDatabase.instance.database;
    _defaultTagsCache = DefaultPlaylistTags.allTags;
    await _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadCurrentPlaylist();
    await _loadPlayHistory();
    await _loadFavorites();
    await _loadUserPlaylists();
    await _loadCustomTags();
  }

  // ==================== helpers ====================

  Music? _decodeMusic(String payload) {
    try {
      return Music.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String _encodeMusicList(List<Music> musics) =>
      jsonEncode(musics.map((m) => m.toJson()).toList());

  int _findMusicIndex(List<Music> list, Music music) =>
      list.indexWhere((m) => m.id == music.id && m.cid == music.cid);

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

  Playlist? _rowToPlaylist(Map<String, Object?> row) {
    try {
      final tagIdsRaw = row['tag_ids'] as String?;
      final tagIds = tagIdsRaw == null
          ? <String>[]
          : (jsonDecode(tagIdsRaw) as List).cast<String>();
      return Playlist(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        coverUrl: row['cover_url'] as String?,
        songCount: (row['song_count'] as int?) ?? 0,
        totalDuration: Duration(
          seconds: (row['total_duration_sec'] as int?) ?? 0,
        ),
        tagIds: tagIds,
        source: PlaylistSource.values.firstWhere(
          (e) => e.name == (row['source'] as String?),
          orElse: () => PlaylistSource.user,
        ),
        playCount: (row['play_count'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updated_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        ),
        lastPlayedAt: row['last_played_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['last_played_at'] as int),
        isDefault: ((row['is_default'] as int?) ?? 0) != 0,
        createdBy: row['created_by'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _replacePayload(
    String table,
    Music m, {
    String? wherePlaylistId,
  }) async {
    await _dbChecked.update(
      table,
      {'payload': jsonEncode(m.toJson())},
      where: wherePlaylistId == null
          ? 'music_id = ? AND cid = ?'
          : 'playlist_id = ? AND music_id = ? AND cid = ?',
      whereArgs: wherePlaylistId == null
          ? [m.id, m.cid]
          : [wherePlaylistId, m.id, m.cid],
    );
  }

  // ==================== loaders ====================

  Future<void> _loadCurrentPlaylist() async {
    final rows = await _dbChecked.query('current_track', orderBy: 'seq ASC');
    _currentPlaylist.value = rows
        .map((r) => _decodeMusic(r['payload'] as String))
        .whereType<Music>()
        .toList();
    if (_currentPlaylist.value.isEmpty) {
      _currentIndex.value = null;
    } else if (_currentIndex.value == null ||
        _currentIndex.value! >= _currentPlaylist.value.length) {
      _currentIndex.value = null;
    }
  }

  Future<void> _loadPlayHistory() async {
    final rows = await _dbChecked.query(
      'play_history',
      orderBy: 'played_at DESC',
    );
    _playHistory.value = rows
        .map((r) => _decodeMusic(r['payload'] as String))
        .whereType<Music>()
        .toList();
  }

  Future<void> _loadFavorites() async {
    final rows = await _dbChecked.query('favorite');
    _favorites.value = rows
        .map((r) => _decodeMusic(r['payload'] as String))
        .whereType<Music>()
        .toList();
  }

  Future<void> _loadUserPlaylists() async {
    final rows = await _dbChecked.query(
      'playlist',
      where: 'is_default = ?',
      whereArgs: [0],
      orderBy: 'updated_at DESC',
    );
    _userPlaylists.value = rows
        .map(_rowToPlaylist)
        .whereType<Playlist>()
        .toList();
  }

  Future<void> _loadCustomTags() async {
    final rows = await _dbChecked.query('custom_tag');
    final customs = rows
        .map((r) {
          try {
            return PlaylistTag.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<PlaylistTag>()
        .toList();
    _allTags.value = [..._defaultTagsCache, ...customs];
  }

  // ==================== getters ====================

  ValueListenable<List<Music>> get currentPlaylist => _currentPlaylist;
  ValueListenable<int?> get currentIndex => _currentIndex;
  ValueListenable<List<Music>> get playHistory => _playHistory;
  ValueListenable<List<Music>> get favorites => _favorites;
  ValueListenable<List<Playlist>> get userPlaylists => _userPlaylists;
  ValueListenable<List<PlaylistTag>> get allTags => _allTags;
  ValueListenable<Playlist?> get currentPlaylistDetail =>
      _currentPlaylistDetail;

  List<Music> get playHistorySnapshot => _playHistory.value;
  List<Music> get favoritesSnapshot => _favorites.value;
  List<Playlist> get userPlaylistsSnapshot => _userPlaylists.value;

  Music? get currentMusic {
    final idx = _currentIndex.value;
    if (idx == null || idx < 0 || idx >= _currentPlaylist.value.length) {
      return null;
    }
    return _currentPlaylist.value[idx];
  }

  int get playlistLength => _currentPlaylist.value.length;
  int? get currentIndexSync => _currentIndex.value;
  int get historyCount => _playHistory.value.length;
  int get favoritesCount => _favorites.value.length;
  int get userPlaylistsCount => _userPlaylists.value.length;

  bool isSystemPlaylist(String playlistId) =>
      DefaultPlaylists.getById(playlistId) != null;

  List<Playlist> get systemPlaylists => DefaultPlaylists.all;

  // ==================== current playlist ====================

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _currentPlaylist.value.length) {
      _currentIndex.value = index;
    } else {
      _currentIndex.value = null;
    }
  }

  Future<void> addToPlaylist(Music music) async {
    await _addUniqueToCurrentPlaylist([music]);
  }

  Future<void> addAllToPlaylist(List<Music> musics) async {
    if (musics.isEmpty) return;
    await _addUniqueToCurrentPlaylist(musics);
  }

  Future<void> _addUniqueToCurrentPlaylist(List<Music> musics) async {
    final existing = _currentPlaylist.value
        .map((m) => '${m.id}_${m.cid}')
        .toSet();
    final fresh = <Music>[];
    for (final m in musics) {
      if (!existing.contains('${m.id}_${m.cid}')) {
        existing.add('${m.id}_${m.cid}');
        fresh.add(m);
      }
    }
    if (fresh.isEmpty) return;

    final db = _dbChecked;
    await db.transaction((txn) async {
      for (final m in fresh) {
        await txn.insert('current_track', {
          'music_id': m.id,
          'cid': m.cid,
          'payload': jsonEncode(m.toJson()),
        });
      }
    });
    await _loadCurrentPlaylist();
  }

  Future<void> updateToPlaylist(Music music) async {
    final idx = _findMusicIndex(_currentPlaylist.value, music);
    if (idx == -1) return;
    await _dbChecked.update(
      'current_track',
      {'payload': jsonEncode(music.toJson())},
      where: 'music_id = ? AND cid = ?',
      whereArgs: [music.id, music.cid],
    );
    final newList = List<Music>.from(_currentPlaylist.value);
    newList[idx] = music;
    _currentPlaylist.value = newList;
  }

  Future<void> removeFromPlaylist(Music music) async {
    final list = _currentPlaylist.value;
    final removeIdx = _findMusicIndex(list, music);
    if (removeIdx == -1) return;

    final currentIdx = _currentIndex.value;
    if (currentIdx != null) {
      if (removeIdx == currentIdx) {
        if (list.length - 1 > 0) {
          _currentIndex.value = removeIdx < list.length - 1
              ? removeIdx
              : removeIdx - 1;
        } else {
          _currentIndex.value = null;
        }
      } else if (removeIdx < currentIdx) {
        _currentIndex.value = currentIdx - 1;
      }
    }

    await _dbChecked.delete(
      'current_track',
      where: 'music_id = ? AND cid = ?',
      whereArgs: [music.id, music.cid],
    );
    await _loadCurrentPlaylist();
  }

  Future<void> clearPlaylist() async {
    await _dbChecked.delete('current_track');
    _currentPlaylist.value = [];
    _currentIndex.value = null;
  }

  Future<void> insertToPlaylist(Music music, int index) async {
    if (index < 0 || index > _currentPlaylist.value.length) return;
    final list = List<Music>.from(_currentPlaylist.value);
    list.insert(index, music);
    await _rewriteCurrentPlaylistInOrder(list);
  }

  Future<void> moveInPlaylist(int from, int to) async {
    if (from == to) return;
    final list = _currentPlaylist.value;
    if (from < 0 || from >= list.length || to < 0 || to >= list.length) return;

    final currentIdx = _currentIndex.value;
    if (currentIdx != null) {
      if (from == currentIdx) {
        _currentIndex.value = to;
      } else if (from < currentIdx && to >= currentIdx) {
        _currentIndex.value = currentIdx - 1;
      } else if (from > currentIdx && to <= currentIdx) {
        _currentIndex.value = currentIdx + 1;
      }
    }

    final moved = List<Music>.from(list);
    final m = moved.removeAt(from);
    moved.insert(to, m);
    await _rewriteCurrentPlaylistInOrder(moved);
  }

  Future<void> _rewriteCurrentPlaylistInOrder(List<Music> musics) async {
    if (musics.isEmpty) {
      await clearPlaylist();
      return;
    }
    final db = _dbChecked;
    await db.transaction((txn) async {
      await txn.delete('current_track');
      for (final m in musics) {
        await txn.insert('current_track', {
          'music_id': m.id,
          'cid': m.cid,
          'payload': jsonEncode(m.toJson()),
        });
      }
    });
    await _loadCurrentPlaylist();
  }

  int? getNextIndex(PlayMode playMode, {Random? random}) {
    final currentIdx = _currentIndex.value;
    final list = _currentPlaylist.value;
    if (currentIdx == null || list.isEmpty) return null;
    switch (playMode) {
      case PlayMode.sequential:
        return (currentIdx + 1) % list.length;
      case PlayMode.loop:
        return currentIdx;
      case PlayMode.shuffle:
        final rng = random ?? Random();
        var idx = rng.nextInt(list.length);
        while (idx == currentIdx && list.length > 1) {
          idx = rng.nextInt(list.length);
        }
        return idx;
    }
  }

  int? getPreviousIndex(PlayMode playMode, {Random? random}) {
    final currentIdx = _currentIndex.value;
    final list = _currentPlaylist.value;
    if (currentIdx == null || list.isEmpty) return null;
    switch (playMode) {
      case PlayMode.sequential:
        return (currentIdx - 1 + list.length) % list.length;
      case PlayMode.loop:
        return currentIdx;
      case PlayMode.shuffle:
        final rng = random ?? Random();
        var idx = rng.nextInt(list.length);
        while (idx == currentIdx && list.length > 1) {
          idx = rng.nextInt(list.length);
        }
        return idx;
    }
  }

  // ==================== play history ====================

  Future<void> addToPlayHistory(Music music) async {
    final db = _dbChecked;
    await db.transaction((txn) async {
      await txn.delete(
        'play_history',
        where: 'music_id = ? AND cid = ?',
        whereArgs: [music.id, music.cid],
      );
      final maxRow = await txn.rawQuery(
        'SELECT MAX(played_at) AS mx FROM play_history',
      );
      final mx = (maxRow.first['mx'] as int?) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final playedAt = now > mx ? now : mx + 1;

      await txn.insert('play_history', {
        'music_id': music.id,
        'cid': music.cid,
        'payload': jsonEncode(music.toJson()),
        'played_at': playedAt,
      });

      final cutoffRow = await txn.rawQuery(
        'SELECT played_at FROM play_history '
        'ORDER BY played_at DESC LIMIT 1 OFFSET ?',
        [_maxHistorySize - 1],
      );
      if (cutoffRow.isNotEmpty) {
        final cutoff = cutoffRow.first['played_at'] as int;
        await txn.delete(
          'play_history',
          where: 'played_at < ?',
          whereArgs: [cutoff],
        );
      }
    });
    await _loadPlayHistory();
  }

  Future<void> clearPlayHistory() async {
    await _dbChecked.delete('play_history');
    _playHistory.value = [];
  }

  // ==================== favorites ====================

  bool isFavorite(Music music) {
    return _findMusicIndex(_favorites.value, music) != -1;
  }

  Future<bool> toggleFavorite(Music music) async {
    if (isFavorite(music)) {
      await removeFromFavorites(music);
      return false;
    } else {
      await addToFavorites(music);
      return true;
    }
  }

  Future<void> addToFavorites(Music music) async {
    final favorited = music.copyWith(isFavorite: true);
    await _dbChecked.insert('favorite', {
      'music_id': music.id,
      'cid': music.cid,
      'payload': jsonEncode(favorited.toJson()),
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _favorites.value = [..._favorites.value, favorited];
    await _propagateFavoriteFlag(favorited, true);
  }

  Future<void> removeFromFavorites(Music music) async {
    if (_findMusicIndex(_favorites.value, music) == -1) return;
    final unfavorited = music.copyWith(isFavorite: false);
    await _dbChecked.delete(
      'favorite',
      where: 'music_id = ? AND cid = ?',
      whereArgs: [music.id, music.cid],
    );
    final newFavs = List<Music>.from(_favorites.value)
      ..removeWhere((m) => m.id == music.id && m.cid == music.cid);
    _favorites.value = newFavs;
    await _propagateFavoriteFlag(unfavorited, false);
  }

  /// 把 `isFavorite` 标志同步到当前播放列表 / 播放历史的镜像和落盘行里，
  /// 与历史 `_updateFavoriteStatusInLists` 等价。
  Future<void> _propagateFavoriteFlag(Music updated, bool isFavorite) async {
    final list = _currentPlaylist.value;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == updated.id && list[i].cid == updated.cid) {
        final newList = List<Music>.from(list);
        newList[i] = updated;
        _currentPlaylist.value = newList;
        await _replacePayload('current_track', updated);
        break;
      }
    }

    final history = _playHistory.value;
    for (var i = 0; i < history.length; i++) {
      if (history[i].id == updated.id && history[i].cid == updated.cid) {
        final newHistory = List<Music>.from(history);
        newHistory[i] = updated;
        _playHistory.value = newHistory;
        await _replacePayload('play_history', updated);
        break;
      }
    }

    for (final playlist in _userPlaylists.value) {
      final rows = await _dbChecked.query(
        'playlist_song',
        where: 'playlist_id = ? AND music_id = ? AND cid = ?',
        whereArgs: [playlist.id, updated.id, updated.cid],
      );
      if (rows.isNotEmpty) {
        await _replacePayload(
          'playlist_song',
          updated,
          wherePlaylistId: playlist.id,
        );
      }
    }
  }

  // ==================== user playlists (CRUD) ====================

  Playlist? getPlaylistInfo(String playlistId) {
    try {
      return _userPlaylists.value.firstWhere((p) => p.id == playlistId);
    } catch (_) {
      return null;
    }
  }

  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    if (isSystemPlaylist(playlistId)) {
      return _buildSystemPlaylistDetail(playlistId);
    }
    final info = getPlaylistInfo(playlistId);
    if (info == null) return null;
    final songs = await loadPlaylistSongs(playlistId);
    return info.copyWith(songs: songs);
  }

  Future<Playlist?> getSystemPlaylistDetail(String playlistId) async {
    if (!isSystemPlaylist(playlistId)) return null;
    return _buildSystemPlaylistDetail(playlistId);
  }

  Future<Playlist?> _buildSystemPlaylistDetail(String playlistId) async {
    final sys = DefaultPlaylists.getById(playlistId);
    if (sys == null) return null;
    final songs = await getSystemPlaylistSongs(playlistId);
    return sys.copyWith(songs: songs, songCount: songs.length);
  }

  Future<List<Music>> getSystemPlaylistSongs(String playlistId) async {
    switch (playlistId) {
      case 'favorites':
        return _favorites.value;
      case 'history':
        return _playHistory.value;
      case 'recommended':
        return loadPlaylistSongs('recommended');
      default:
        return <Music>[];
    }
  }

  Future<Playlist> createPlaylist({
    required String name,
    String? description,
    List<String> tagIds = const [],
    PlaylistSource source = PlaylistSource.user,
  }) async {
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'playlist_${now.millisecondsSinceEpoch}',
      name: name,
      description: description,
      tagIds: tagIds,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    await _dbChecked.insert('playlist', _playlistRow(playlist));
    await _loadUserPlaylists();
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (isSystemPlaylist(playlistId)) return;
    final db = _dbChecked;
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_song',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'playlist',
        where: 'id = ? AND is_default = 0',
        whereArgs: [playlistId],
      );
    });
    await _loadUserPlaylists();
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    await _updateUserPlaylist(playlistId, {
      'name': newName,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updatePlaylistDescription(
    String playlistId,
    String? description,
  ) async {
    await _updateUserPlaylist(playlistId, {
      'description': description,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _updateUserPlaylist(
    String playlistId,
    Map<String, Object?> patch,
  ) async {
    if (isSystemPlaylist(playlistId)) return;
    final count = await _dbChecked.update(
      'playlist',
      patch,
      where: 'id = ? AND is_default = 0',
      whereArgs: [playlistId],
    );
    if (count > 0) {
      await _loadUserPlaylists();
    }
  }

  Future<void> addTagToPlaylist(String playlistId, String tagId) async {
    final info = getPlaylistInfo(playlistId);
    if (info == null || info.tagIds.contains(tagId)) return;
    await _updateUserPlaylist(playlistId, {
      'tag_ids': jsonEncode([...info.tagIds, tagId]),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeTagFromPlaylist(String playlistId, String tagId) async {
    final info = getPlaylistInfo(playlistId);
    if (info == null || !info.tagIds.contains(tagId)) return;
    await _updateUserPlaylist(playlistId, {
      'tag_ids': jsonEncode(info.tagIds.where((t) => t != tagId).toList()),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  List<Playlist> filterPlaylistsByTag(String tagId) {
    return _userPlaylists.value.where((p) => p.tagIds.contains(tagId)).toList();
  }

  void setCurrentPlaylistDetail(Playlist? playlist) {
    _currentPlaylistDetail.value = playlist;
  }

  // ==================== playlist songs ====================

  Future<List<Music>> loadPlaylistSongs(String playlistId) async {
    final rows = await _dbChecked.query(
      'playlist_song',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return rows
        .map((r) => _decodeMusic(r['payload'] as String))
        .whereType<Music>()
        .toList();
  }

  Future<bool> addSongsToPlaylist(
    String playlistId,
    List<Music> newSongs,
  ) async {
    if (newSongs.isEmpty) return false;
    if (isSystemPlaylist(playlistId) && playlistId != 'recommended') {
      return false;
    }

    final db = _dbChecked;
    var added = 0;
    var updatedRowCountOrCover = false;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'playlist_song',
        columns: ['music_id', 'cid'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      final existingKeys = existing
          .map((r) => '${r['music_id']}_${r['cid']}')
          .toSet();
      final maxPosRow = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) AS mx '
        'FROM playlist_song WHERE playlist_id = ?',
        [playlistId],
      );
      var pos = (maxPosRow.first['mx'] as int?) ?? -1;

      for (final m in newSongs) {
        final key = '${m.id}_${m.cid}';
        if (existingKeys.contains(key)) continue;
        existingKeys.add(key);
        pos += 1;
        await txn.insert('playlist_song', {
          'playlist_id': playlistId,
          'music_id': m.id,
          'cid': m.cid,
          'position': pos,
          'payload': jsonEncode(m.toJson()),
          'added_at': DateTime.now().millisecondsSinceEpoch,
        });
        added += 1;
      }

      if (added > 0) {
        final countRow = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM playlist_song WHERE playlist_id = ?',
          [playlistId],
        );
        final count = (countRow.first['c'] as int?) ?? 0;

        String? coverUrl;
        if (!isSystemPlaylist(playlistId)) {
          final firstRow = await txn.query(
            'playlist_song',
            where: 'playlist_id = ?',
            whereArgs: [playlistId],
            orderBy: 'position ASC',
            limit: 1,
          );
          if (firstRow.isNotEmpty) {
            final m = _decodeMusic(firstRow.first['payload'] as String);
            if (m != null && m.safeCoverUrl.isNotEmpty) {
              coverUrl = m.safeCoverUrl;
            }
          }
        }

        final update = <String, Object?>{
          'song_count': count,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        };
        if (coverUrl != null) update['cover_url'] = coverUrl;

        final updated = await txn.update(
          'playlist',
          update,
          where: 'id = ?',
          whereArgs: [playlistId],
        );
        if (updated > 0) updatedRowCountOrCover = true;
      }
    });

    if (updatedRowCountOrCover) {
      await _loadUserPlaylists();
    }
    return added > 0;
  }

  Future<bool> addSongToUserPlaylist(String playlistId, Music music) async {
    return addSongsToPlaylist(playlistId, [music]);
  }

  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<Music> songsToRemove,
  ) async {
    if (isSystemPlaylist(playlistId) && playlistId != 'recommended') return;
    final db = _dbChecked;
    var touchedPlaylistRow = false;
    await db.transaction((txn) async {
      for (final m in songsToRemove) {
        await txn.delete(
          'playlist_song',
          where: 'playlist_id = ? AND music_id = ? AND cid = ?',
          whereArgs: [playlistId, m.id, m.cid],
        );
      }
      final countRow = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM playlist_song WHERE playlist_id = ?',
        [playlistId],
      );
      final count = (countRow.first['c'] as int?) ?? 0;
      final updated = await txn.update(
        'playlist',
        {
          'song_count': count,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [playlistId],
      );
      if (updated > 0) touchedPlaylistRow = true;
    });
    if (touchedPlaylistRow) {
      await _loadUserPlaylists();
    }
  }

  /// 用传入歌曲列表的首项封面做歌单封面（仅当现有封面为空时使用）。
  /// 兼容旧 `updatePlaylistCover` 行为。
  Future<void> updatePlaylistCover(String playlistId, List<Music> songs) async {
    if (isSystemPlaylist(playlistId)) return;
    if (songs.isEmpty) return;
    final coverUrl = songs.first.safeCoverUrl;
    if (coverUrl.isEmpty) return;
    final info = getPlaylistInfo(playlistId);
    if (info == null) return;
    if ((info.coverUrl ?? '').isNotEmpty && info.coverUrl == coverUrl) {
      return;
    }
    await _updateUserPlaylist(playlistId, {
      'cover_url': coverUrl,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ==================== tags ====================

  Map<TagCategory, List<PlaylistTag>> getTagsByCategory() {
    final tags = _allTags.value;
    return {
      for (final c in TagCategory.values)
        c: tags.where((t) => t.category == c).toList(),
    };
  }

  PlaylistTag? getTagById(String tagId) {
    try {
      return _allTags.value.firstWhere((t) => t.id == tagId);
    } catch (_) {
      return null;
    }
  }

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
    await _dbChecked.insert('custom_tag', {
      'id': tag.id,
      'payload': jsonEncode(tag.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _allTags.value = [..._allTags.value, tag];
    return tag;
  }

  // ==================== watch helpers (compat) ====================

  ValueListenable<List<Music>> watchPlayHistory() => _playHistory;
  ValueListenable<List<Music>> watchFavorites() => _favorites;
  ValueListenable<List<Playlist>> watchUserPlaylists() => _userPlaylists;
  ValueListenable<List<PlaylistTag>> watchTags() => _allTags;

  // ==================== export / import / clear ====================

  /// 备份导出: 返回与旧 `data_migration_page.dart` 兼容的 key 字符串 map。
  Future<Map<String, String?>> exportForBackup() async {
    final db = _dbChecked;
    final result = <String, String?>{};

    result['play_history'] = _encodeMusicList(_playHistory.value);
    result['favorites'] = _encodeMusicList(_favorites.value);

    final playlistRows = await db.query('playlist');
    final playlistObjects = <Map<String, dynamic>>[];
    for (final row in playlistRows) {
      final p = _rowToPlaylist(row);
      if (p == null) continue;
      final json = p.toJson();
      playlistObjects.add(json);
      final id = p.id;
      result['playlist_info_$id'] = jsonEncode(json);
      final songs = await loadPlaylistSongs(id);
      result['playlist_songs_$id'] = _encodeMusicList(songs);
    }
    result['user_playlists_enhanced'] = jsonEncode(playlistObjects);
    result['user_playlists'] = jsonEncode(
      playlistObjects.map((j) => j['id']).toList(),
    );

    return result;
  }

  /// 备份导入: 接受 `data_migration_page.dart` 旧格式的 map。
  Future<void> importFromBackup(Map<String, dynamic> data) async {
    final db = _dbChecked;
    await db.transaction((txn) async {
      await txn.delete('current_track');
      await txn.delete('play_history');
      await txn.delete('favorite');
      await txn.delete('playlist_song');
      await txn.delete('playlist');
      await txn.delete('custom_tag');

      Future<void> insertMusicList(
        Object? raw,
        String table, {
        required bool withPlayedAt,
      }) async {
        if (raw is! String) return;
        try {
          final list = jsonDecode(raw) as List;
          var i = 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          for (final entry in list) {
            try {
              final m = Music.fromJson(entry as Map<String, dynamic>);
              final row = <String, Object?>{
                'music_id': m.id,
                'cid': m.cid,
                'payload': jsonEncode(m.toJson()),
              };
              if (withPlayedAt) {
                row['played_at'] = now - i++;
              } else if (table == 'favorite') {
                row['added_at'] = now;
              }
              await txn.insert(
                table,
                row,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } catch (_) {}
          }
        } catch (_) {}
      }

      await insertMusicList(
        data['play_history'],
        'play_history',
        withPlayedAt: true,
      );
      await insertMusicList(data['favorites'], 'favorite', withPlayedAt: false);

      final playlistEntries = <Map<String, dynamic>>[];
      if (data['user_playlists_enhanced'] is String) {
        try {
          final list = jsonDecode(data['user_playlists_enhanced']) as List;
          for (final entry in list) {
            if (entry is Map<String, dynamic>) playlistEntries.add(entry);
          }
        } catch (_) {}
      }
      data.forEach((key, value) {
        if (key.startsWith('playlist_info_') && value is String) {
          try {
            final j = jsonDecode(value) as Map<String, dynamic>;
            final id = key.substring('playlist_info_'.length);
            j['id'] ??= id;
            if (!playlistEntries.any((e) => e['id'] == id)) {
              playlistEntries.add(j);
            }
          } catch (_) {}
        }
      });

      for (final raw in playlistEntries) {
        try {
          final p = Playlist.fromJson(raw);
          await txn.insert(
            'playlist',
            _playlistRow(p),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {}
      }

      for (final key in data.keys) {
        if (!key.startsWith('playlist_songs_')) continue;
        if (data[key] is! String) continue;
        final id = key.substring('playlist_songs_'.length);
        try {
          final list = jsonDecode(data[key] as String);
          if (list is! List) continue;
          var pos = 0;
          for (final entry in list) {
            try {
              final m = Music.fromJson(entry as Map<String, dynamic>);
              await txn.insert('playlist_song', {
                'playlist_id': id,
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
    });

    await _loadAll();
  }

  /// 清除所有列表数据。Settings/cookies/login 不在范围内。
  Future<void> clearAllUserData() async {
    final db = _dbChecked;
    await db.transaction((txn) async {
      await txn.delete('current_track');
      await txn.delete('play_history');
      await txn.delete('favorite');
      await txn.delete('playlist_song');
      await txn.delete('playlist');
      await txn.delete('custom_tag');
      await txn.delete('kv');
    });
    await _loadAll();
  }

  Future<void> dispose() async {
    // sqflite 数据库由 AppDatabase 单例持有, 此处不需要关闭
  }
}
