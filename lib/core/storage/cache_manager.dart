import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 音乐文件缓存管理器
final musicCacheManager = CacheManager(
  Config(
    'music_cache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 50,
  ),
);

/// 图片缓存管理器
final imageCacheManager = CacheManager(
  Config(
    'image_cache',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 100,
  ),
);

/// 歌词缓存管理器 —— 由 [LyricsService] 写入,持久化已解析的
/// `LyricsPayload` JSON 与源列表,避免每次进入详情页都重新发起 lyrics_now 请求。
final lyricsCacheManager = CacheManager(
  Config(
    'lyrics_cache',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 200,
  ),
);

/// 缓存清理功能
abstract class LocalStorage {
  static Future<void> clearCache() async {
    await musicCacheManager.emptyCache();
    await imageCacheManager.emptyCache();
    await lyricsCacheManager.emptyCache();
  }

  static Future<Map<String, String>> getCacheSize() async {
    final musicSize = await _getCacheSize(musicCacheManager);
    final imageSize = await _getCacheSize(imageCacheManager);
    final lyricsSize = await _getCacheSize(lyricsCacheManager);
    return {
      'music': musicSize.toString(),
      'image': imageSize.toString(),
      'lyrics': lyricsSize.toString(),
    };
  }

  static Future<int> _getCacheSize(CacheManager manager) async {
    try {
      // 获取缓存文件目录
      return await manager.store.getCacheSize();
    } catch (e) {
      return 0;
    }
  }

  static Future<String> getCachePath() async {
    final cacheDir = await getTemporaryDirectory();
    return path.join(cacheDir.path, 'cache');
  }
}
