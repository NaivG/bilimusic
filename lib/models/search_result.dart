import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 搜索结果类型枚举
enum SearchResultType {
  video, // 视频/单曲
  album, // 专辑/合集
  author, // 创作者/UP主
  bangumi, // 番剧
  topic, // 话题
  upuser, // 用户
}

/// 搜索结果基类
class SearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final SearchResultType type;

  /// 视频分P信息（延迟加载）
  List<Page> pages;

  /// 分P数量
  int get pageCount => pages.length;

  /// 是否为系列（多P）视频
  bool get isSeries => pages.length > 1;

  SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.type,
    List<Page>? pages,
  }) : pages = pages ?? [];

  factory SearchResult.fromJson(
    Map<String, dynamic> json,
    SearchResultType type,
  ) {
    // 处理富文本标题
    String title = json['title'] ?? '';
    if (title.contains('<em') && title.contains('</em>')) {
      title = title.replaceAll(RegExp(r'<[^>]*>'), '');
    }
    title = title
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    // 构建封面URL
    String coverUrl = json['pic'] ?? '';
    if (coverUrl.isNotEmpty && !coverUrl.startsWith('http')) {
      coverUrl = 'https:$coverUrl';
    }

    return SearchResult(
      id:
          json['bvid'] ??
          json['mid']?.toString() ??
          json['season_id']?.toString() ??
          '',
      title: title,
      subtitle: _buildSubtitle(json, type),
      coverUrl: coverUrl,
      type: type,
    );
  }

  static String _buildSubtitle(
    Map<String, dynamic> json,
    SearchResultType type,
  ) {
    switch (type) {
      case SearchResultType.video:
        return '${json['author'] ?? '未知作者'} - ${json['tag'] ?? ''}';
      case SearchResultType.author:
        return '${json['fans'] ?? ''} 粉丝';
      case SearchResultType.album:
        return json['author'] ?? '未知作者';
      case SearchResultType.bangumi:
        return json['desc'] ?? '';
      case SearchResultType.topic:
        return '${json['thread'] ?? 0} 讨论';
      case SearchResultType.upuser:
        return json['uname'] ?? '';
    }
  }

  /// 转换为Music对象（用于播放）
  Music toMusic({List<Page>? pages}) {
    final musicPages = pages ?? this.pages;
    // 设置 cid 为第一个分P的 cid（如果存在）
    final firstCid = musicPages.isNotEmpty ? musicPages.first.cid : '';
    return Music(
      id: id,
      cid: firstCid,
      title: title,
      artist: subtitle.split(' - ').first,
      album: subtitle.split(' - ').last,
      coverUrl: coverUrl,
      duration: musicPages.isNotEmpty
          ? Duration(seconds: int.tryParse(musicPages.first.duration) ?? 0)
          : null,
      audioUrl: '',
      pages: musicPages,
    );
  }

  /// 获取视频分P信息
  Future<List<Page>> fetchPages() async {
    if (type != SearchResultType.video || id.isEmpty) {
      return [];
    }

    // 如果已经有分P信息，直接返回
    if (pages.isNotEmpty) {
      return pages;
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$id'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          final data = json['data'];
          final pagesData = data['pages'] ?? [];
          pages = pagesData
              .map<Page>(
                (pageJson) => Page.fromJson(
                  pageJson,
                  pageIndex: pagesData.indexOf(pageJson),
                ),
              )
              .toList();
          return pages;
        }
      }
    } catch (_) {
      // 网络错误或解析失败
    }
    return [];
  }

  /// 创建副本并更新分P信息
  SearchResult copyWithPages(List<Page> newPages) {
    return SearchResult(
      id: id,
      title: title,
      subtitle: subtitle,
      coverUrl: coverUrl,
      type: type,
      pages: newPages,
    );
  }
}

/// 搜索响应模型
class SearchResponse {
  final String keyword;
  final List<SearchResult> results;
  final bool hasMore;
  final int page;
  final int totalResults;

  SearchResponse({
    required this.keyword,
    required this.results,
    required this.hasMore,
    required this.page,
    required this.totalResults,
  });

  factory SearchResponse.empty(String keyword) {
    return SearchResponse(
      keyword: keyword,
      results: [],
      hasMore: false,
      page: 0,
      totalResults: 0,
    );
  }
}

/// 搜索状态
enum SearchStatus { initial, loading, success, empty, error }

/// 搜索错误类型
enum SearchError { networkError, serverError, noResults, invalidQuery, unknown }
