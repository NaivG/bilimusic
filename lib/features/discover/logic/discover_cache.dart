import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';

/// 热歌榜的缓存有效期。榜单周更，留一天余量足够。
const hotSongsTtl = Duration(hours: 12);

/// 音乐区排行的缓存有效期（榜单动态更新）。
const musicRankTtl = Duration(hours: 6);

/// 发现流的缓存有效期（推荐流换得快，半小时后允许自动重取）。
const musicFeedTtl = Duration(minutes: 30);

/// 手动刷新的最小间隔：防连点把接口打爆（这几个端点都有频率限制）。
const hotSongsMinRefreshInterval = Duration(minutes: 10);
const musicRankMinRefreshInterval = Duration(minutes: 10);
const musicFeedMinRefreshInterval = Duration(minutes: 1);

/// [fetchedAt] 是否还在 [ttl] 之内；没有抓取时间一律算过期。
bool isCacheFresh(DateTime? fetchedAt, Duration ttl, {DateTime? now}) {
  if (fetchedAt == null) return false;
  return (now ?? DateTime.now()).difference(fetchedAt) < ttl;
}

/// 热歌榜缓存快照。
class HotSongsCache {
  final List<HotSong> songs;
  final int listId;
  final int period;
  final DateTime? publishedAt;
  final DateTime fetchedAt;

  const HotSongsCache({
    required this.songs,
    required this.fetchedAt,
    this.listId = 0,
    this.period = 0,
    this.publishedAt,
  });

  Map<String, dynamic> toJson() => {
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'listId': listId,
    'period': period,
    'publishedAt': publishedAt?.millisecondsSinceEpoch,
    'songs': songs.map((s) => s.toJson()).toList(),
  };

  static HotSongsCache? fromJson(Map<String, dynamic> json) {
    final songs = json['songs'];
    final fetchedAt = json['fetchedAt'];
    if (songs is! List || fetchedAt is! num) return null;
    return HotSongsCache(
      songs: songs
          .whereType<Map>()
          .map((e) => HotSong.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.title.isNotEmpty)
          .toList(),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt()),
      listId: (json['listId'] as num?)?.toInt() ?? 0,
      period: (json['period'] as num?)?.toInt() ?? 0,
      publishedAt: json['publishedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['publishedAt'] as num).toInt(),
            )
          : null,
    );
  }
}

/// 音乐区排行缓存快照。
class MusicRankCache {
  final List<Music> items;
  final String note;
  final DateTime fetchedAt;

  const MusicRankCache({
    required this.items,
    required this.fetchedAt,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'note': note,
    'items': items.map((m) => m.toJson()).toList(),
  };

  static MusicRankCache? fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final fetchedAt = json['fetchedAt'];
    if (items is! List || fetchedAt is! num) return null;
    return MusicRankCache(
      items: _decodeMusics(items),
      note: (json['note'] ?? '').toString(),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt()),
    );
  }
}

/// 发现流缓存快照。
class MusicFeedCache {
  final List<Music> items;
  final int page;
  final DateTime fetchedAt;

  const MusicFeedCache({
    required this.items,
    required this.fetchedAt,
    this.page = 1,
  });

  Map<String, dynamic> toJson() => {
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'page': page,
    'items': items.map((m) => m.toJson()).toList(),
  };

  static MusicFeedCache? fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final fetchedAt = json['fetchedAt'];
    if (items is! List || fetchedAt is! num) return null;
    return MusicFeedCache(
      items: _decodeMusics(items),
      page: (json['page'] as num?)?.toInt() ?? 1,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt()),
    );
  }
}

List<Music> _decodeMusics(List<dynamic> raw) => raw
    .whereType<Map>()
    .map((e) => Music.fromJson(Map<String, dynamic>.from(e)))
    .where((m) => m.id.isNotEmpty)
    .toList();

/// 发现页的落盘缓存。
///
/// 三类数据各占一个键。打开页面先铺缓存、判过期再发请求。
class DiscoverCache {
  DiscoverCache({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  // v2：榜单条目带相关视频身份，与旧结构不兼容
  static const String hotSongsKey = 'discover_hot_songs_v2';
  static const String musicRankKey = 'discover_music_rank_v1';
  static const String musicFeedKey = 'discover_music_feed_v1';

  Future<HotSongsCache?> readHotSongs() async =>
      _read(hotSongsKey, HotSongsCache.fromJson);

  Future<void> writeHotSongs(HotSongsCache value) =>
      _write(hotSongsKey, value.toJson());

  Future<MusicRankCache?> readMusicRank() async =>
      _read(musicRankKey, MusicRankCache.fromJson);

  Future<void> writeMusicRank(MusicRankCache value) =>
      _write(musicRankKey, value.toJson());

  Future<MusicFeedCache?> readMusicFeed() async =>
      _read(musicFeedKey, MusicFeedCache.fromJson);

  Future<void> writeMusicFeed(MusicFeedCache value) =>
      _write(musicFeedKey, value.toJson());

  /// 整个缓存清掉（设置页「清除用户数据」以外的场景暂不调用）。
  Future<void> clear() async {
    final prefs = await _preferences();
    await prefs.remove(hotSongsKey);
    await prefs.remove(musicRankKey);
    await prefs.remove(musicFeedKey);
  }

  Future<T?> _read<T>(
    String key,
    T? Function(Map<String, dynamic>) decode,
  ) async {
    final prefs = await _preferences();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decode(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 缓存坏了就当没有，下一次成功会覆盖
      return null;
    }
  }

  Future<void> _write(String key, Map<String, dynamic> value) async {
    final prefs = await _preferences();
    await prefs.setString(key, jsonEncode(value));
  }
}
