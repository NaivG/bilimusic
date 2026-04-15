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

/// 缓存清理功能
abstract class LocalStorage {
  static Future<void> clearCache() async {
    await musicCacheManager.emptyCache();
    await imageCacheManager.emptyCache();
  }

  static Future<Map<String, String>> getCacheSize() async {
    final musicSize = await _getCacheSize(musicCacheManager);
    final imageSize = await _getCacheSize(imageCacheManager);
    return {'music': musicSize.toString(), 'image': imageSize.toString()};
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