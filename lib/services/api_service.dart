import 'dart:convert';
import 'package:flutter/cupertino.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/bili_item.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

/// API服务
/// 职责：统一处理所有网络API调用
class ApiService {
  /// 获取视频详情（返回 BiliItem，推荐使用）
  Future<BiliItem?> getBiliItemDetails(String bvid) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$bvid'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return BiliItem.fromViewApi(json['data']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting BiliItem details: $e');
      return null;
    }
  }

  /// 获取视频详情（兼容旧接口，内部调用 getBiliItemDetails）
  ///
  /// [pageIndex] - 可选参数，指定返回第几个分P（从0开始）
  /// [targetCid] - 可选参数，指定返回cid对应的分P
  /// 如果同时指定了pageIndex和targetCid，优先使用targetCid
  Future<Music> getVideoDetails(
    String bvid, {
    int? pageIndex,
    String? targetCid,
  }) async {
    final biliItem = await getBiliItemDetails(bvid);
    if (biliItem != null && biliItem.pages.isNotEmpty) {
      // 如果指定了targetCid，查找匹配的分P
      if (targetCid != null && targetCid.isNotEmpty) {
        final matchedPage = biliItem.pages.firstWhere(
          (page) => page.cid == targetCid,
          orElse: () => biliItem.pages.first,
        );
        return matchedPage;
      }
      // 如果指定了pageIndex，返回对应分P
      if (pageIndex != null &&
          pageIndex >= 0 &&
          pageIndex < biliItem.pages.length) {
        return biliItem.pages[pageIndex];
      }
      // 默认返回第一个分P（保持向后兼容）
      return biliItem.pages.first;
    }
    // 失败时返回仅含 bvid 的 Music，避免抛异常
    return Music(
      id: bvid,
      title: '未知标题',
      artist: '未知作者',
      album: '',
      coverUrl: '',
      audioUrl: '',
    );
  }

  /// 获取音频URL
  /// 优先使用 music.cid，如果为空则 fallback 到 music.pages[0].cid
  Future<String> getAudioUrl(Music music) async {
    try {
      // 获取 CID：优先用 music.cid，其次用 pages[0].cid
      String cid = music.cid;
      if (cid.isEmpty && music.pages.isNotEmpty) {
        cid = music.pages[0].cid;
      }

      // 构建缓存键
      final cacheKey = cid.isNotEmpty ? "${music.id}_$cid" : music.id;

      final cachedFile = await musicCacheManager.getFileFromCache(cacheKey);
      if (cachedFile != null) {
        return cachedFile.file.path;
      }

      // 如果 cid 仍然为空，先获取视频详情
      if (cid.isEmpty) {
        final biliItem = await getBiliItemDetails(music.id);
        if (biliItem != null && biliItem.pages.isNotEmpty) {
          cid = biliItem.pages.first.cid;
        }
      }

      if (cid.isEmpty) {
        debugPrint('Failed to get cid for ${music.id}');
        return '';
      }

      // 获取音频URL
      final audioResponse = await http.get(
        Uri.parse(
          'https://api.bilibili.com/x/player/playurl?bvid=${music.id}&cid=$cid&fnval=16',
        ),
        headers: NetworkConfig.biliHeaders,
      );

      if (audioResponse.statusCode == 200) {
        final audioJson = jsonDecode(audioResponse.body);

        if (audioJson['code'] == 0 &&
            audioJson['data'] != null &&
            audioJson['data']['dash'] != null &&
            audioJson['data']['dash']['audio'] != null &&
            audioJson['data']['dash']['audio'].isNotEmpty) {
          final audioUrl = audioJson['data']['dash']['audio'][0]['baseUrl'];

          final file = await musicCacheManager.downloadFile(
            audioUrl,
            key: "${music.id}_$cid",
            authHeaders: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
              'Referer': 'https://www.bilibili.com',
            },
          );
          return file.file.path;
        }
      }

      debugPrint('Failed to get audio URL for ${music.id}');
      return '';
    } catch (e, stackTrace) {
      debugPrint('Error getting audio URL for ${music.id}: $e');
      debugPrint('Stack trace: $stackTrace');
      return '';
    }
  }

  /// 搜索音乐
  Future<List<Music>> searchMusic(String query) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.bilibili.com/x/web-interface/search/all/v2?keyword=$query',
        ),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data']['result'] != null) {
          final results = json['data']['result'];
          final musicResults = <Music>[];

          // 解析搜索结果
          for (final result in results) {
            if (result['result_type'] == 'video') {
              final videos = result['data'] ?? [];
              for (final video in videos) {
                musicResults.add(
                  Music(
                    id: video['bvid'] ?? '',
                    title: video['title'] ?? '未知标题',
                    artist: video['author'] ?? '未知艺术家',
                    album: '搜索',
                    coverUrl: video['pic']!.toString() + "@672w_378h",
                    duration: Duration(seconds: video['duration'] ?? 180),
                    audioUrl: '',
                    pages: [],
                    isFavorite: false,
                  ),
                );
              }
            }
          }

          return musicResults;
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error searching music: $e');
      return [];
    }
  }

  /// 获取推荐音乐
  Future<List<Music>> getRecommendedMusic() async {
    try {
      // 这里可以调用B站的推荐API
      // 暂时返回空列表，实际项目中需要实现
      return [];
    } catch (e) {
      debugPrint('Error getting recommended music: $e');
      return [];
    }
  }

  /// 获取热门音乐
  Future<List<Music>> getPopularMusic() async {
    try {
      // 这里可以调用B站的热门API
      // 暂时返回空列表，实际项目中需要实现
      return [];
    } catch (e) {
      debugPrint('Error getting popular music: $e');
      return [];
    }
  }
}
