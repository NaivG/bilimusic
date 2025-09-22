import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/models/music.dart';

/// 播放列表信息类
class PlaylistInfo {
  final String id;
  final String name;
  final String? coverUrl;
  final int createdAt;
  final int updatedAt;

  PlaylistInfo({
    required this.id,
    required this.name,
    this.coverUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coverUrl': coverUrl,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory PlaylistInfo.fromJson(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: json['id'],
      name: json['name'],
      coverUrl: json['coverUrl'],
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }
}

/// 播放列表管理器
class PlaylistManager {
  static const String _playlistIndexKey = 'user_playlists';
  late SharedPreferences _prefs;

  /// 初始化播放列表管理器
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 创建新的播放列表
  Future<String> createPlaylist(String name, {String? coverUrl}) async {
    final id = 'playlist_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}';
    
    final playlistInfo = PlaylistInfo(
      id: id,
      name: name,
      coverUrl: coverUrl,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 保存播放列表信息
    await _savePlaylistInfo(playlistInfo);
    
    // 创建空的播放列表
    await _savePlaylistSongs(id, []);

    return id;
  }

  /// 获取所有播放列表信息
  Future<List<PlaylistInfo>> getAllPlaylists() async {
    final playlistIdsJson = _prefs.getString(_playlistIndexKey);
    if (playlistIdsJson == null) {
      return [];
    }

    try {
      final List<dynamic> playlistIds = jsonDecode(playlistIdsJson);
      final playlists = <PlaylistInfo>[];

      for (var id in playlistIds) {
        final playlistInfo = await getPlaylistInfo(id);
        if (playlistInfo != null) {
          playlists.add(playlistInfo);
        }
      }

      return playlists;
    } catch (e) {
      debugPrint('Failed to load playlists: $e');
      return [];
    }
  }

  /// 获取播放列表信息
  Future<PlaylistInfo?> getPlaylistInfo(String id) async {
    final playlistInfoJson = _prefs.getString('playlist_info_$id');
    if (playlistInfoJson == null) return null;

    try {
      final Map<String, dynamic> json = jsonDecode(playlistInfoJson);
      return PlaylistInfo.fromJson(json);
    } catch (e) {
      debugPrint('Failed to parse playlist info: $e');
      return null;
    }
  }

  /// 保存播放列表信息
  Future<void> _savePlaylistInfo(PlaylistInfo playlistInfo) async {
    final playlistInfoJson = jsonEncode(playlistInfo.toJson());
    await _prefs.setString('playlist_info_${playlistInfo.id}', playlistInfoJson);

    // 更新播放列表索引
    final playlistIdsJson = _prefs.getString(_playlistIndexKey);
    Set<String> playlistIds = <String>{};
    
    if (playlistIdsJson != null) {
      try {
        playlistIds = Set<String>.from(jsonDecode(playlistIdsJson));
      } catch (e) {
        debugPrint('Failed to parse playlist index: $e');
      }
    }
    
    playlistIds.add(playlistInfo.id);
    await _prefs.setString(_playlistIndexKey, jsonEncode(playlistIds.toList()));
  }

  /// 获取播放列表中的歌曲
  Future<List<Music>> getPlaylistSongs(String id) async {
    final playlistSongsJson = _prefs.getString('playlist_songs_$id');
    if (playlistSongsJson == null) return [];

    try {
      final List<dynamic> songsJson = jsonDecode(playlistSongsJson);
      return songsJson.map((json) => Music.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Failed to parse playlist songs: $e');
      return [];
    }
  }

  /// 保存播放列表中的歌曲
  Future<void> _savePlaylistSongs(String id, List<Music> songs) async {
    final songsJson = jsonEncode(songs.map((song) => song.toJson()).toList());
    await _prefs.setString('playlist_songs_$id', songsJson);
  }

  /// 向播放列表添加歌曲
  Future<void> addSongToPlaylist(String playlistId, Music song) async {
    final songs = await getPlaylistSongs(playlistId);
    
    // 检查歌曲是否已存在
    final exists = songs.any((s) => 
      s.id == song.id && 
      (s.pages.isEmpty && song.pages.isEmpty ||
       s.pages.isNotEmpty && song.pages.isNotEmpty &&
       s.pages[0].cid == song.pages[0].cid));
    
    if (!exists) {
      songs.add(song);
      await _savePlaylistSongs(playlistId, songs);
      
      // 更新更新时间
      final playlistInfo = await getPlaylistInfo(playlistId);
      if (playlistInfo != null) {
        final updatedInfo = PlaylistInfo(
          id: playlistInfo.id,
          name: playlistInfo.name,
          coverUrl: playlistInfo.coverUrl,
          createdAt: playlistInfo.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _savePlaylistInfo(updatedInfo);
      }
    }
  }

  /// 从播放列表移除歌曲
  Future<void> removeSongFromPlaylist(String playlistId, Music song) async {
    final songs = await getPlaylistSongs(playlistId);
    
    songs.removeWhere((s) => 
      s.id == song.id && 
      (s.pages.isEmpty && song.pages.isEmpty ||
       s.pages.isNotEmpty && song.pages.isNotEmpty &&
       s.pages[0].cid == song.pages[0].cid));
    
    await _savePlaylistSongs(playlistId, songs);
    
    // 更新更新时间
    final playlistInfo = await getPlaylistInfo(playlistId);
    if (playlistInfo != null) {
      final updatedInfo = PlaylistInfo(
        id: playlistInfo.id,
        name: playlistInfo.name,
        coverUrl: playlistInfo.coverUrl,
        createdAt: playlistInfo.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _savePlaylistInfo(updatedInfo);
    }
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String id) async {
    // 删除播放列表信息和歌曲
    await _prefs.remove('playlist_info_$id');
    await _prefs.remove('playlist_songs_$id');

    // 从索引中移除
    final playlistIdsJson = _prefs.getString(_playlistIndexKey);
    if (playlistIdsJson != null) {
      try {
        Set<String> playlistIds = Set<String>.from(jsonDecode(playlistIdsJson));
        playlistIds.remove(id);
        await _prefs.setString(_playlistIndexKey, jsonEncode(playlistIds.toList()));
      } catch (e) {
        debugPrint('Failed to update playlist index: $e');
      }
    }
  }

  /// 重命名播放列表
  Future<void> renamePlaylist(String id, String newName) async {
    final playlistInfo = await getPlaylistInfo(id);
    if (playlistInfo != null) {
      final updatedInfo = PlaylistInfo(
        id: playlistInfo.id,
        name: newName,
        coverUrl: playlistInfo.coverUrl,
        createdAt: playlistInfo.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _savePlaylistInfo(updatedInfo);
    }
  }
}