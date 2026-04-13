import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:bilimusic/models/search_result.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:rxdart/rxdart.dart';

/// 搜索服务 - 处理B站搜索API调用
class SearchService {
  static final SearchService _instance = SearchService._internal();
  factory SearchService() => _instance;
  SearchService._internal();

  // AV号转BV号
  String av2bv(int aid) {
    const xorCode = 23442827791579;
    const base = 58;
    const data = "FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf";

    List<String> bytes = [
      'B',
      'V',
      '1',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
    ];
    int bvIndex = bytes.length - 1;

    BigInt tmp = (BigInt.one << 51) | BigInt.from(aid);
    tmp = tmp ^ BigInt.from(xorCode);

    while (tmp > BigInt.zero) {
      final remainder = tmp % BigInt.from(base);
      bytes[bvIndex] = data[remainder.toInt()];
      tmp = tmp ~/ BigInt.from(base);
      bvIndex--;
    }

    _swap(bytes, 3, 9);
    _swap(bytes, 4, 7);

    return bytes.join();
  }

  void _swap(List<String> list, int i, int j) {
    final temp = list[i];
    list[i] = list[j];
    list[j] = temp;
  }

  /// 解析搜索响应
  Future<SearchResponse> search(String query, {SearchResultType? type}) async {
    if (query.trim().isEmpty) {
      return SearchResponse.empty(query);
    }

    final trimmedQuery = query.trim();

    // 检查BV号
    if (trimmedQuery.startsWith('BV1')) {
      return _searchByBvid(trimmedQuery);
    }

    // 检查AV号
    if (trimmedQuery.toUpperCase().startsWith('AV')) {
      try {
        final aidString = trimmedQuery
            .substring(2)
            .replaceAll(RegExp(r'[^0-9]'), '');
        if (aidString.isNotEmpty) {
          final aid = int.parse(aidString);
          final bvid = av2bv(aid);
          return _searchByBvid(bvid);
        }
      } catch (e) {
        return SearchResponse.empty(query);
      }
    }

    // 执行搜索
    return _performSearch(query, type: type);
  }

  /// 通过BV号搜索
  Future<SearchResponse> _searchByBvid(String bvid) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$bvid'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          final data = json['data'];
          final result = SearchResult(
            id: bvid,
            title: data['title'],
            subtitle: data['owner']['name'],
            coverUrl: data['pic'] + "@672w_378h",
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
      }
    } catch (e) {
      // 忽略错误
    }
    return SearchResponse.empty(bvid);
  }

  /// 执行搜索请求
  Future<SearchResponse> _performSearch(
    String query, {
    SearchResultType? type,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.bilibili.com/x/web-interface/search/all/v2?keyword=$query',
        ),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return _parseSearchResults(json['data'], query);
        }
      }
    } catch (e) {
      return SearchResponse(
        keyword: query,
        results: [],
        hasMore: false,
        page: 0,
        totalResults: 0,
      );
    }
    return SearchResponse.empty(query);
  }

  /// 解析搜索结果
  SearchResponse _parseSearchResults(Map<String, dynamic> data, String query) {
    final List<SearchResult> allResults = [];
    int totalResults = 0;

    final results = data['result'] as List? ?? [];

    for (var result in results) {
      final resultType = result['result_type'] as String?;
      final items = result['data'] as List? ?? [];

      SearchResultType? mappedType;
      switch (resultType) {
        case 'video':
          mappedType = SearchResultType.video;
          break;
        case 'album':
          mappedType = SearchResultType.album;
          break;
        case 'author':
          mappedType = SearchResultType.author;
          break;
        case 'media_bangumi':
          mappedType = SearchResultType.bangumi;
          break;
        case 'topic':
          mappedType = SearchResultType.topic;
          break;
        case 'upuser':
          mappedType = SearchResultType.upuser;
          break;
      }

      if (mappedType != null) {
        for (var item in items) {
          allResults.add(SearchResult.fromJson(item, mappedType));
        }
        totalResults += items.length;
      }
    }

    return SearchResponse(
      keyword: query,
      results: allResults,
      hasMore:
          data['numPages'] != null &&
          (data['page'] ?? 1) < (data['numPages'] ?? 1),
      page: data['page'] ?? 1,
      totalResults: totalResults,
    );
  }

  /// 防抖搜索
  Stream<SearchResponse> searchWithDebounce(
    String query, {
    Duration debounceTime = const Duration(milliseconds: 300),
  }) {
    return Stream.value(
      query,
    ).debounceTime(debounceTime).asyncMap((q) => search(q));
  }

  /// 获取指定类型的结果
  List<SearchResult> filterByType(
    List<SearchResult> results,
    SearchResultType type,
  ) {
    return results.where((r) => r.type == type).toList();
  }

  /// 获取所有支持的结果类型
  List<SearchResultType> getAvailableTypes(List<SearchResult> results) {
    return results.map((r) => r.type).toSet().toList();
  }
}
