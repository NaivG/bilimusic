/// Page信息缓存
/// 用于存储Page的额外信息，如封面URL等
class PageInfo {
  final String bvid;
  final String cid;
  final String? coverUrl;
  final DateTime cachedAt;

  static const int cacheValidHours = 24;

  PageInfo({
    required this.bvid,
    required this.cid,
    this.coverUrl,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inHours >= cacheValidHours;

  String get key => '${bvid}_$cid';
}

/// 音频URL缓存
class AudioUrlCache {
  final String url;
  final DateTime cachedAt;

  static const int cacheValidMinutes = 120; // 2小时

  AudioUrlCache({required this.url, DateTime? cachedAt})
    : cachedAt = cachedAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inMinutes >= cacheValidMinutes;

  String get key => url;
}

/// Page缓存管理器
/// 职责：
/// - 缓存Page详细信息（避免重复请求view API）
/// - 缓存Page音频URL（减少playurl API调用）
/// - LRU淘汰策略
class PageCache {
  static const int _maxCacheSize = 100; // 最多缓存100个Page

  /// Page信息缓存
  final Map<String, PageInfo> _pageInfoCache = {};

  /// 音频URL缓存
  final Map<String, AudioUrlCache> _audioUrlCache = {};

  /// 访问顺序（用于LRU）
  final List<String> _accessOrder = [];

  /// 获取Page信息
  PageInfo? getPageInfo(String bvid, String cid) {
    final key = '${bvid}_$cid';
    final info = _pageInfoCache[key];

    if (info != null) {
      // 移动到末尾（最近使用）
      _moveToEnd(key);
      return info;
    }
    return null;
  }

  /// 缓存Page信息
  void cachePageInfo(PageInfo info) {
    final key = info.key;

    // 如果已存在，先移除
    if (_pageInfoCache.containsKey(key)) {
      _accessOrder.remove(key);
    } else {
      // LRU: 达到上限时移除最旧的
      _evictIfNeeded();
    }

    _pageInfoCache[key] = info;
    _accessOrder.add(key);
  }

  /// 获取音频URL
  String? getAudioUrl(String bvid, String cid) {
    final key = '${bvid}_$cid';
    final cached = _audioUrlCache[key];

    if (cached != null && !cached.isExpired) {
      return cached.url;
    }
    return null;
  }

  /// 缓存音频URL（有效期2小时）
  void cacheAudioUrl(String bvid, String cid, String url) {
    final key = '${bvid}_$cid';

    // 如果已存在，先移除
    if (_audioUrlCache.containsKey(key)) {
      _audioUrlCache.remove(key);
    } else {
      // LRU: 达到上限时移除最旧的
      _evictAudioIfNeeded();
    }

    _audioUrlCache[key] = AudioUrlCache(url: url);
  }

  /// 清除指定视频的Page缓存
  void invalidateByBvid(String bvid) {
    final keysToRemove = _pageInfoCache.keys
        .where((key) => key.startsWith('${bvid}_'))
        .toList();

    for (final key in keysToRemove) {
      _pageInfoCache.remove(key);
      _accessOrder.remove(key);
    }

    // 清除音频URL缓存
    final audioKeysToRemove = _audioUrlCache.keys
        .where((key) => key.startsWith('${bvid}_'))
        .toList();

    for (final key in audioKeysToRemove) {
      _audioUrlCache.remove(key);
    }
  }

  /// 清除指定Page的缓存
  void invalidate(String bvid, String cid) {
    final key = '${bvid}_$cid';
    _pageInfoCache.remove(key);
    _accessOrder.remove(key);
    _audioUrlCache.remove(key);
  }

  /// 清除过期缓存
  void cleanExpired() {
    // 清除过期的Page信息
    final expiredInfoKeys = _pageInfoCache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();

    for (final key in expiredInfoKeys) {
      _pageInfoCache.remove(key);
      _accessOrder.remove(key);
    }

    // 清除过期的音频URL
    _audioUrlCache.removeWhere((key, value) => value.isExpired);
  }

  /// 清除所有缓存
  void clear() {
    _pageInfoCache.clear();
    _audioUrlCache.clear();
    _accessOrder.clear();
  }

  /// 获取缓存大小
  int get size => _pageInfoCache.length;

  /// 获取音频缓存大小
  int get audioCacheSize => _audioUrlCache.length;

  /// LRU: 移动到末尾（最近使用）
  void _moveToEnd(String key) {
    if (_accessOrder.contains(key)) {
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }
  }

  /// LRU: 达到上限时移除最旧的
  void _evictIfNeeded() {
    while (_pageInfoCache.length >= _maxCacheSize && _accessOrder.isNotEmpty) {
      final oldestKey = _accessOrder.removeAt(0);
      _pageInfoCache.remove(oldestKey);
    }
  }

  /// LRU: 音频缓存达到上限时移除
  void _evictAudioIfNeeded() {
    while (_audioUrlCache.length >= _maxCacheSize) {
      final firstKey = _audioUrlCache.keys.first;
      _audioUrlCache.remove(firstKey);
    }
  }
}

/// 全局Page缓存实例
final pageCacheManager = PageCache();
