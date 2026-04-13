import 'package:bilimusic/models/music.dart';

/// 歌单歌曲内存缓存
/// 职责：
/// - LRU 缓存策略
/// - 歌单歌曲的内存缓存
/// - 懒加载支持
class MusicCache {
  static const int _maxCacheSize = 50; // 最多缓存50个歌单

  /// LRU 缓存，使用 LinkedHashMap 保持插入顺序
  final Map<String, List<Music>> _cache = {};

  /// 获取缓存的歌曲
  List<Music>? getSongs(String playlistId) {
    if (!_cache.containsKey(playlistId)) {
      return null;
    }
    // LRU: 移动到末尾（最近使用）
    _moveToEnd(playlistId);
    return _cache[playlistId];
  }

  /// 设置缓存
  void setSongs(String playlistId, List<Music> songs) {
    // 如果已存在，先移除
    if (_cache.containsKey(playlistId)) {
      _cache.remove(playlistId);
    }

    // LRU: 达到上限时移除最旧的
    while (_cache.length >= _maxCacheSize) {
      _removeOldest();
    }

    _cache[playlistId] = List.from(songs);
  }

  /// 清除指定歌单缓存
  void invalidate(String playlistId) {
    _cache.remove(playlistId);
  }

  /// 检查是否已缓存
  bool hasCache(String playlistId) {
    return _cache.containsKey(playlistId);
  }

  /// 获取缓存大小
  int get size => _cache.length;

  /// 清除所有缓存
  void clear() {
    _cache.clear();
  }

  /// 预加载歌曲到缓存
  void preload(String playlistId, List<Music> songs) {
    setSongs(playlistId, songs);
  }

  /// LRU: 移动到末尾（最近使用）
  void _moveToEnd(String playlistId) {
    final songs = _cache.remove(playlistId);
    if (songs != null) {
      _cache[playlistId] = songs;
    }
  }

  /// LRU: 移除最旧的条目
  void _removeOldest() {
    if (_cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }
  }
}
