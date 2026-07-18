import 'package:flutter/cupertino.dart' show debugPrint;

import 'package:bilimusic/api/bili_client.dart';
import 'package:bilimusic/api/bili_exception.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/models/bili_fav_folder.dart';
import 'package:bilimusic/models/bili_fav_resource.dart';
import 'package:bilimusic/models/bili_item.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/search_result.dart';
import 'package:bilimusic/utils/av_bv.dart';

/// B 站 API 服务。所有 HTTP 请求统一走 [BiliClient]。
class ApiService {
  ApiService({BiliClient? client}) : _client = client ?? BiliClient();

  final BiliClient _client;

  // ====================================================================
  //  视频详情
  // ====================================================================

  /// 获取 [BiliItem]（包含分P、UP 主、Stat 等完整信息）。
  Future<BiliItem?> getBiliItemDetails(String bvid) async {
    try {
      final data = await _client.get(
        '/x/web-interface/view',
        query: {'bvid': bvid},
      );
      if (data is Map<String, dynamic>) {
        return BiliItem.fromViewApi(data);
      }
      return null;
    } on BiliException catch (e) {
      debugPrint('[ApiService] getBiliItemDetails($bvid): $e');
      return null;
    }
  }

  /// 兼容旧接口：返回 [Music]。可选 [pageIndex] / [targetCid] 选择分P。
  ///
  /// 失败时返回仅含 bvid 的占位 [Music]，避免上游链路过早崩。
  Future<Music> getVideoDetails(
    String bvid, {
    int? pageIndex,
    String? targetCid,
  }) async {
    final biliItem = await getBiliItemDetails(bvid);
    if (biliItem != null && biliItem.pages.isNotEmpty) {
      if (targetCid != null && targetCid.isNotEmpty) {
        final matched = biliItem.pages.firstWhere(
          (p) => p.cid == targetCid,
          orElse: () => biliItem.pages.first,
        );
        return matched;
      }
      if (pageIndex != null &&
          pageIndex >= 0 &&
          pageIndex < biliItem.pages.length) {
        return biliItem.pages[pageIndex];
      }
      return biliItem.pages.first;
    }
    return Music(
      id: bvid,
      title: '未知标题',
      artist: '未知作者',
      album: '',
      coverUrl: '',
      audioUrl: '',
    );
  }

  // ====================================================================
  //  音频 URL
  // ====================================================================

  /// 获取可播放的音频 URL（命中本地缓存则返回本地路径，否则走 `/x/player/playurl` 后下载）。
  ///
  /// 失败返回 `''` —— 该方法历史上是「尽力而为」语义，未改为抛异常以避免
  /// 破坏 [PlayerCoordinator] 的 fallback 逻辑（无 URL 即停在 stopped 态）。
  Future<String> getAudioUrl(Music music) async {
    try {
      String cid = music.cid;
      if (cid.isEmpty && music.pages.isNotEmpty) {
        cid = music.pages[0].cid;
      }

      final cacheKey = cid.isNotEmpty ? '${music.id}_$cid' : music.id;
      final cached = await musicCacheManager.getFileFromCache(cacheKey);
      if (cached != null) {
        return cached.file.path;
      }

      if (cid.isEmpty) {
        final biliItem = await getBiliItemDetails(music.id);
        if (biliItem != null && biliItem.pages.isNotEmpty) {
          cid = biliItem.pages.first.cid;
        }
      }
      if (cid.isEmpty) {
        debugPrint('[ApiService] getAudioUrl(${music.id}): no cid');
        return '';
      }

      final data = await _client.get(
        '/x/player/playurl',
        query: {'bvid': music.id, 'cid': cid, 'fnval': '16'},
      );

      final dash = (data as Map<String, dynamic>?)?['dash'];
      final audios = dash is Map ? dash['audio'] as List? : null;
      if (audios == null || audios.isEmpty) {
        debugPrint('[ApiService] getAudioUrl(${music.id}): no dash audio');
        return '';
      }
      final audioUrl = audios.first['baseUrl']?.toString() ?? '';
      if (audioUrl.isEmpty) {
        return '';
      }

      final file = await musicCacheManager.downloadFile(
        audioUrl,
        key: '${music.id}_$cid',
        authHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
          'Referer': 'https://www.bilibili.com',
        },
      );
      return file.file.path;
    } on BiliException catch (e) {
      debugPrint('[ApiService] getAudioUrl(${music.id}): $e');
      return '';
    } catch (e, st) {
      debugPrint('[ApiService] getAudioUrl(${music.id}) crash: $e');
      debugPrint('Stack trace: $st');
      return '';
    }
  }

  // ====================================================================
  //  搜索
  // ====================================================================

  /// 关键词 / BV / AV 入口。统一返回 [SearchResponse]。
  Future<SearchResponse> search(String query, {SearchResultType? type}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return SearchResponse.empty(query);
    }

    if (trimmed.startsWith('BV1')) {
      return _searchByBvid(trimmed);
    }

    if (trimmed.toUpperCase().startsWith('AV')) {
      final digits = trimmed.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        return SearchResponse.empty(query);
      }
      final aid = int.tryParse(digits);
      if (aid == null) {
        return SearchResponse.empty(query);
      }
      return _searchByBvid(av2bv(aid));
    }

    return _searchByKeyword(trimmed, type: type);
  }

  Future<SearchResponse> _searchByBvid(String bvid) async {
    final biliItem = await getBiliItemDetails(bvid);
    if (biliItem == null) {
      return SearchResponse.empty(bvid);
    }
    final cover = biliItem.pic;
    final result = SearchResult(
      id: bvid,
      title: biliItem.title,
      subtitle: biliItem.owner.name,
      coverUrl: cover.isNotEmpty ? '$cover@672w_378h' : cover,
      type: SearchResultType.video,
    );
    return SearchResponse(
      keyword: bvid,
      results: [result],
      hasMore: false,
      page: 1,
      totalResults: 1,
    );
  }

  Future<SearchResponse> _searchByKeyword(
    String query, {
    SearchResultType? type,
  }) async {
    try {
      final data = await _client.getJson(
        '/x/web-interface/search/all/v2',
        query: {'keyword': query},
      );
      return _parseSearchResults(data, query);
    } on BiliApiException catch (e) {
      if (e.code == -101) {
        debugPrint('[ApiService] search($query): not logged in');
      } else {
        debugPrint('[ApiService] search($query): $e');
      }
      return SearchResponse(
        keyword: query,
        results: const [],
        hasMore: false,
        page: 0,
        totalResults: 0,
      );
    } on BiliNetworkException catch (e) {
      debugPrint('[ApiService] search($query): network $e');
      return SearchResponse.empty(query);
    }
  }

  SearchResponse _parseSearchResults(Map<String, dynamic> data, String query) {
    final results = data['result'] is List ? data['result'] as List : const [];
    final List<SearchResult> all = [];
    var total = 0;

    for (final result in results) {
      if (result is! Map) continue;
      final resultType = result['result_type']?.toString();
      final items = result['data'] is List ? result['data'] as List : const [];
      final mapped = _mapResultType(resultType);
      if (mapped == null) continue;
      for (final item in items) {
        if (item is Map) {
          all.add(SearchResult.fromJson(_stringKeys(item), mapped));
        }
      }
      total += items.length;
    }

    final page = data['page'] is int ? data['page'] as int : 1;
    final numPages = data['numPages'] is int ? data['numPages'] as int : 1;

    return SearchResponse(
      keyword: query,
      results: all,
      hasMore: page < numPages,
      page: page,
      totalResults: total,
    );
  }

  SearchResultType? _mapResultType(String? raw) {
    switch (raw) {
      case 'video':
        return SearchResultType.video;
      case 'album':
        return SearchResultType.album;
      case 'author':
        return SearchResultType.author;
      case 'media_bangumi':
        return SearchResultType.bangumi;
      case 'topic':
        return SearchResultType.topic;
      case 'upuser':
        return SearchResultType.upuser;
    }
    return null;
  }

  Map<String, dynamic> _stringKeys(Map<dynamic, dynamic> source) {
    return source.map((k, v) => MapEntry(k.toString(), v));
  }

  // ====================================================================
  //  收藏夹 / 歌单
  // ====================================================================

  /// 获取指定用户创建的所有收藏夹。
  Future<List<BiliFavFolder>> fetchUserCreatedFolders(int upMid) async {
    try {
      final data = await _client.get(
        '/x/v3/fav/folder/created/list-all',
        query: {'up_mid': '$upMid'},
      );
      final list = (data as Map<String, dynamic>?)?['list'];
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => BiliFavFolder.fromCreatedList(_stringKeys(e)))
            .toList();
      }
      return const [];
    } on BiliApiException catch (e) {
      if (e.code == -101) {
        debugPrint('[FavAPI] 未登录，无法获取收藏夹');
      } else {
        debugPrint('[FavAPI] fetchUserCreatedFolders: $e');
      }
      return const [];
    } on BiliNetworkException catch (e) {
      debugPrint('[FavAPI] fetchUserCreatedFolders network: $e');
      return const [];
    }
  }

  /// 获取指定用户收藏的收藏夹（分页）。
  Future<List<BiliFavFolder>> fetchCollectedFolders(
    int upMid, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final data = await _client.get(
        '/x/v3/fav/folder/collected/list',
        query: {
          'up_mid': '$upMid',
          'ps': '$pageSize',
          'pn': '$page',
          'platform': 'web',
        },
      );
      final list = (data as Map<String, dynamic>?)?['list'];
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => BiliFavFolder.fromCollectedList(_stringKeys(e)))
            .toList();
      }
      return const [];
    } on BiliException catch (e) {
      debugPrint('[FavAPI] fetchCollectedFolders: $e');
      return const [];
    }
  }

  /// 获取收藏夹资源列表（分页）。
  Future<FavResourcePage> fetchFolderResources(
    int mediaId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final raw = await _client.getJson(
        '/x/v3/fav/resource/list',
        query: {
          'media_id': '$mediaId',
          'platform': 'web',
          'pn': '$page',
          'ps': '$pageSize',
        },
      );
      final data = raw['data'];
      if (data is! Map) return FavResourcePage.empty();
      final info = (data['info'] is Map) ? data['info'] as Map : const {};
      final medias = (data['medias'] is List)
          ? data['medias'] as List
          : const [];
      final hasMore = data['has_more'] == true;
      final resources = medias
          .whereType<Map>()
          .map((e) => FavResource.fromJson(_stringKeys(e)))
          .toList();

      return FavResourcePage(
        resources: resources,
        hasMore: hasMore,
        title: info['title']?.toString() ?? '',
        cover: info['cover']?.toString() ?? '',
        mediaCount: info['media_count'] is int ? info['media_count'] as int : 0,
      );
    } on BiliException catch (e) {
      debugPrint('[FavAPI] fetchFolderResources: $e');
      return FavResourcePage.empty();
    }
  }

  /// 批量获取指定资源详情。
  Future<List<FavResource>> batchFetchResourceDetails(
    List<FavResourceRef> resources,
  ) async {
    if (resources.isEmpty) return const [];
    try {
      final resourceStr = resources.map((r) => '${r.id}:${r.type}').join(',');
      final data = await _client.get(
        '/x/v3/fav/resource/infos',
        query: {'resources': resourceStr, 'platform': 'web'},
      );
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => FavResource.fromJson(_stringKeys(e)))
            .toList();
      }
      return const [];
    } on BiliException catch (e) {
      debugPrint('[FavAPI] batchFetchResourceDetails: $e');
      return const [];
    }
  }
}
