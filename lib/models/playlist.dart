import 'package:flutter/material.dart';

import 'music.dart';
import 'playlist_tag.dart';

/// 歌单来源枚举
enum PlaylistSource {
  system, // 系统生成（如"我喜欢"、"最近播放"、"每日推荐"）
  user, // 用户创建
  smart, // 智能歌单（基于规则的自动生成）
  imported, // 导入的歌单
}

/// 歌单排序类型
enum PlaylistSortType {
  custom, // 自定义顺序
  nameAsc, // 名称升序
  nameDesc, // 名称降序
  dateAsc, // 创建时间升序
  dateDesc, // 创建时间降序
  songCount, // 歌曲数量
  lastPlayed, // 最近播放
}

/// 歌单模型
class Playlist {
  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final int songCount;
  final Duration totalDuration;
  final List<String> tagIds; // 关联的标签ID列表
  final PlaylistSource source; // 来源
  final int playCount; // 播放次数
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPlayedAt; // 上次播放时间
  final bool isDefault; // 是否为默认歌单
  final String? createdBy; // 创建者（用户ID或系统标识）

  // 关联的歌曲列表（非持久化，用于UI展示）
  List<Music> songs;

  // 内存中缓存的标签（非持久化）
  List<PlaylistTag> _tagsCache;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.coverUrl,
    this.songCount = 0,
    this.totalDuration = Duration.zero,
    this.tagIds = const [],
    this.source = PlaylistSource.user,
    this.playCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.lastPlayedAt,
    this.isDefault = false,
    this.createdBy,
    List<Music>? songs,
  }) : songs = songs ?? [],
       _tagsCache = [];

  /// 获取关联的标签列表
  List<PlaylistTag> get tags {
    if (_tagsCache.isEmpty && tagIds.isNotEmpty) {
      _tagsCache = DefaultPlaylistTags.getByIds(tagIds);
    }
    return _tagsCache;
  }

  /// 设置标签缓存
  void setTags(List<PlaylistTag> tags) {
    _tagsCache = tags;
  }

  /// 获取格式化总时长
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// 是否为系统歌单
  bool get isSystemPlaylist => source == PlaylistSource.system;

  /// 是否为空歌单
  bool get isEmpty => songCount == 0;

  /// 是否有描述
  bool get hasDescription => description != null && description!.isNotEmpty;

  /// 获取显示名称（默认歌单有特殊名称）
  String get displayName {
    if (id == 'favorites') return '我喜欢的音乐';
    if (id == 'history') return '最近播放';
    if (id == 'recommended') return '每日推荐';
    return name;
  }

  /// 获取系统歌单的特殊图标
  IconData? get systemPlaylistIcon {
    if (!isSystemPlaylist) return null;
    switch (id) {
      case 'favorites':
        return Icons.favorite;
      case 'history':
        return Icons.history;
      case 'recommended':
        return Icons.auto_awesome;
      default:
        return Icons.album;
    }
  }

  /// 获取系统歌单的特殊图标颜色
  Color? get systemPlaylistIconColor {
    if (!isSystemPlaylist) return null;
    switch (id) {
      case 'favorites':
        return Colors.red;
      case 'history':
        return Colors.blue;
      case 'recommended':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  /// 获取封面URL（带默认图）
  /// 返回第一个歌曲的封面URL，若列表为空返回空字符串
  String get safeCoverUrl {
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      return coverUrl!;
    }
    if (songs.isNotEmpty) {
      return songs.first.safeCoverUrl;
    }
    return '';
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final songCount = json['songCount'] ?? 0;
    final durationSeconds = json['totalDuration'] ?? 0;

    return Playlist(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      coverUrl: json['coverUrl'],
      songCount: songCount,
      totalDuration: Duration(seconds: durationSeconds),
      tagIds: json['tagIds'] != null ? List<String>.from(json['tagIds']) : [],
      source: PlaylistSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => PlaylistSource.user,
      ),
      playCount: json['playCount'] ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      lastPlayedAt: json['lastPlayedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastPlayedAt'])
          : null,
      isDefault: json['isDefault'] ?? false,
      createdBy: json['createdBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverUrl': coverUrl,
      'songCount': songCount,
      'totalDuration': totalDuration.inSeconds,
      'tagIds': tagIds,
      'source': source.name,
      'playCount': playCount,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
      'isDefault': isDefault,
      'createdBy': createdBy,
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    String? coverUrl,
    int? songCount,
    Duration? totalDuration,
    List<String>? tagIds,
    PlaylistSource? source,
    int? playCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
    bool? isDefault,
    String? createdBy,
    List<Music>? songs,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      songCount: songCount ?? this.songCount,
      totalDuration: totalDuration ?? this.totalDuration,
      tagIds: tagIds ?? this.tagIds,
      source: source ?? this.source,
      playCount: playCount ?? this.playCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      isDefault: isDefault ?? this.isDefault,
      createdBy: createdBy ?? this.createdBy,
      songs: songs ?? this.songs,
    );
  }

  /// 创建默认歌单的便捷方法
  factory Playlist.defaultPlaylist({
    required String id,
    required String name,
    String? description,
    String? coverUrl,
    PlaylistSource source = PlaylistSource.system,
  }) {
    final now = DateTime.now();
    return Playlist(
      id: id,
      name: name,
      description: description,
      coverUrl: coverUrl,
      source: source,
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 创建用户歌单的便捷方法
  factory Playlist.createUserPlaylist({
    required String name,
    String? description,
    List<String> tagIds = const [],
  }) {
    final now = DateTime.now();
    return Playlist(
      id: 'playlist_${now.millisecondsSinceEpoch}',
      name: name,
      description: description,
      tagIds: tagIds,
      source: PlaylistSource.user,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Playlist && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Playlist(id: $id, name: $name, songCount: $songCount)';
}

/// 歌单音乐关联表
class PlaylistMusicRelation {
  final String playlistId;
  final String musicId;
  final String? pageCid; // 分P的CID，用于精确匹配
  final int position; // 在歌单中的位置
  final DateTime addedAt; // 添加时间
  final String? addedFrom; // 来源（搜索/推荐/手动等）

  const PlaylistMusicRelation({
    required this.playlistId,
    required this.musicId,
    this.pageCid,
    required this.position,
    required this.addedAt,
    this.addedFrom,
  });

  factory PlaylistMusicRelation.fromJson(Map<String, dynamic> json) {
    return PlaylistMusicRelation(
      playlistId: json['playlistId'],
      musicId: json['musicId'],
      pageCid: json['pageCid'],
      position: json['position'] ?? 0,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        json['addedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      addedFrom: json['addedFrom'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playlistId': playlistId,
      'musicId': musicId,
      'pageCid': pageCid,
      'position': position,
      'addedAt': addedAt.millisecondsSinceEpoch,
      'addedFrom': addedFrom,
    };
  }

  PlaylistMusicRelation copyWith({
    String? playlistId,
    String? musicId,
    String? pageCid,
    int? position,
    DateTime? addedAt,
    String? addedFrom,
  }) {
    return PlaylistMusicRelation(
      playlistId: playlistId ?? this.playlistId,
      musicId: musicId ?? this.musicId,
      pageCid: pageCid ?? this.pageCid,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      addedFrom: addedFrom ?? this.addedFrom,
    );
  }

  @override
  String toString() =>
      'PlaylistMusicRelation(playlistId: $playlistId, musicId: $musicId, position: $position)';
}

/// 默认系统歌单
class DefaultPlaylists {
  /// 我喜欢的音乐
  static Playlist get favorites => Playlist.defaultPlaylist(
    id: 'favorites',
    name: '我喜欢的音乐',
    description: '你收藏的歌曲都在这里',
  );

  /// 最近播放
  static Playlist get history => Playlist.defaultPlaylist(
    id: 'history',
    name: '最近播放',
    description: '最近播放的歌曲',
  );

  /// 每日推荐（示例）
  static Playlist get recommended => Playlist.defaultPlaylist(
    id: 'recommended',
    name: '每日推荐',
    description: '根据你的口味为你推荐',
  );

  /// 获取所有默认歌单
  static List<Playlist> get all => [favorites, history, recommended];

  /// 根据ID获取默认歌单
  static Playlist? getById(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
