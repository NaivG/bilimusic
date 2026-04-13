import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/page_cache.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Page API服务
/// 职责：
/// - 获取分P音频URL
/// - 获取分P详细信息
/// - 自动缓存管理
class PageService {
  /// 获取分P音频URL
  /// 先检查缓存，如果缓存命中则直接返回，否则请求API并缓存
  Future<String?> getPageAudioUrl(String bvid, String cid) async {
    // 1. 检查缓存
    final cached = pageCacheManager.getAudioUrl(bvid, cid);
    if (cached != null) {
      return cached;
    }

    // 2. 请求API
    final url = await _fetchAudioUrl(bvid, cid);

    // 3. 写入缓存
    if (url != null) {
      pageCacheManager.cacheAudioUrl(bvid, cid, url);
    }

    return url;
  }

  /// 获取分P详细信息
  Future<PageInfo?> getPageInfo(String bvid, String cid) async {
    // 1. 检查缓存
    final cached = pageCacheManager.getPageInfo(bvid, cid);
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    // 2. 请求API获取视频详情
    final response = await http.get(
      Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$bvid'),
      headers: NetworkConfig.biliHeaders,
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['code'] == 0) {
        final data = json['data'];
        final pagesData = data['pages'] ?? [];

        // 遍历找到对应的cid
        for (final page in pagesData) {
          if (page['cid'].toString() == cid) {
            final pageInfo = PageInfo(
              bvid: bvid,
              cid: cid,
              coverUrl: page['first_frame'],
            );

            // 缓存
            pageCacheManager.cachePageInfo(pageInfo);
            return pageInfo;
          }
        }
      }
    }

    return null;
  }

  /// 获取指定分P的音频URL
  Future<String?> _fetchAudioUrl(String bvid, String cid) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&fnval=0&fnver=0&fourk=1',
        ),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          final data = json['data'];
          final durl = data['durl'] as List?;

          if (durl != null && durl.isNotEmpty) {
            return durl.first['url'];
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }

    return null;
  }

  /// 批量获取多个分P的音频URL
  Future<Map<String, String>> getBatchAudioUrls(
    String bvid,
    List<Page> pages,
  ) async {
    final results = <String, String>{};

    for (final page in pages) {
      final url = await getPageAudioUrl(bvid, page.cid);
      if (url != null) {
        results[page.cid] = url;
      }
    }

    return results;
  }

  /// 清除指定视频的Page缓存
  void invalidateVideo(String bvid) {
    pageCacheManager.invalidateByBvid(bvid);
  }

  /// 清除指定分P的缓存
  void invalidatePage(String bvid, String cid) {
    pageCacheManager.invalidate(bvid, cid);
  }

  /// 清除所有过期缓存
  void cleanExpired() {
    pageCacheManager.cleanExpired();
  }
}

/// 全局PageService实例
final pageService = PageService();
