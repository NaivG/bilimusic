import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// 音乐文件缓存管理器
final musicCacheManager = CacheManager(
  Config(
    'music_cache',
    stalePeriod: Duration(days: 7),
    maxNrOfCacheObjects: 50,
  ),
);

// 图片缓存管理器
final imageCacheManager = CacheManager(
  Config(
    'image_cache',
    stalePeriod: Duration(days: 30),
    maxNrOfCacheObjects: 100,
  ),
);

// 缓存清理功能
abstract class LocalStorage {
  static Future<void> clearCache() async {
    await musicCacheManager.emptyCache();
    await imageCacheManager.emptyCache();
  }

  static Future<Map<String, String>> getCacheSize() async {
    final musicSize = await _getCacheSize(musicCacheManager);
    final imageSize = await _getCacheSize(imageCacheManager);
    return {
      'music': '$musicSize MB',
      'image': '$imageSize MB',
    };
  }

  static Future<int> _getCacheSize(CacheManager manager) async {
    try {
      // 获取缓存文件目录
      final appDocDir = await getApplicationSupportDirectory();
      final cacheDir = Directory(path.join(appDocDir.path, manager.config.cacheKey));
      if (!await cacheDir.exists()) {
        return 0;
      }
      
      // 遍历缓存目录下的所有文件
      double total = 0;
      final files = await cacheDir.list().toList();
      for (var file in files) {
        if (file is File) {
          total += (await file.length()).toDouble();
        }
      }
      
      return (total / (1024 * 1024)).toInt();
    } catch (e) {
      return 0;
    }
  }
}