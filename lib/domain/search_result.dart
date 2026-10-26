import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/shared/utils/title_meta_filter.dart';

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

  /// 创作者（视频条目是 UP 主，用户条目就是本人；其余类型为空）。
  ///
  /// 搜索端点把昵称/头像拍平成 `author` / `uname` + `upic`，这里收敛成 [Artist]，
  /// 于是搜索结果也能直接进歌手页。
  final Artist artist;

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
    this.artist = const Artist(),
    List<Page>? pages,
  }) : pages = pages ?? [];

  factory SearchResult.fromJson(
    Map<String, dynamic> json,
    SearchResultType type,
  ) {
    // 处理富文本标题。用户结果没有 title，昵称在 uname 里。
    String title = (json['title'] ?? json['uname'] ?? '').toString();
    if (title.contains('<em') && title.contains('</em>')) {
      title = title.replaceAll(RegExp(r'<[^>]*>'), '');
    }
    title = title
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    // 实验性标题元数据过滤：只对视频稿件的标题做。作者名 / 话题名 /
    // 番剧名不过滤——避免误伤「MV制作组」这类用户名（开关关闭时原样返回）。
    if (type == SearchResultType.video) {
      title = TitleMetaFilter.maybeClean(title);
    }

    // 构建封面URL。视频/番剧在 pic，用户在 upic。
    String coverUrl = (json['pic'] ?? json['upic'] ?? '').toString();
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
      artist: _buildArtist(json, type),
    );
  }

  /// 取创作者：[SearchResultType.video] 是稿件的 UP 主（扁平 `author` + `mid` +
  /// `upic`），[SearchResultType.author] / [SearchResultType.upuser] 是用户本人
  /// （`uname` + `upic`；`bili_user` 结果也走这条）。其余类型端点不给创作者，留空。
  static Artist _buildArtist(Map<String, dynamic> json, SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return Artist.fromFlat(json);
      case SearchResultType.author:
      case SearchResultType.upuser:
        final artist = Artist.fromFlat(json, nameKey: 'uname');
        // 兼容把昵称放在 author 里的旧条目
        if (artist.name.trim().isNotEmpty) return artist;
        return Artist.fromFlat(json, nameKey: 'author');
      case SearchResultType.album:
      case SearchResultType.bangumi:
      case SearchResultType.topic:
        return const Artist();
    }
  }

  static String _buildSubtitle(
    Map<String, dynamic> json,
    SearchResultType type,
  ) {
    switch (type) {
      case SearchResultType.video:
        return '${json['author'] ?? '未知作者'} - ${json['tag'] ?? ''}';
      case SearchResultType.author:
      case SearchResultType.upuser:
        final fans = _formatCount(json['fans']);
        final videos = _formatCount(json['videos']);
        if (fans.isNotEmpty || videos.isNotEmpty) {
          return [
            if (fans.isNotEmpty) '$fans粉丝',
            if (videos.isNotEmpty) '$videos投稿',
          ].join(' · ');
        }
        return (json['usign'] ?? '').toString();
      case SearchResultType.album:
        return (json['author'] ?? '未知作者').toString();
      case SearchResultType.bangumi:
        return (json['desc'] ?? '').toString();
      case SearchResultType.topic:
        return '${json['thread'] ?? 0} 讨论';
    }
  }

  /// 把粉丝数 / 投稿数收成「1.2万」这种短文案；解析不了时返回空串。
  static String _formatCount(Object? raw) {
    final value = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '');
    if (value == null || value <= 0) return '';
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(1)}亿';
    }
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    return '$value';
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
      artist: artist,
      album: subtitle.split(' - ').last,
      coverUrl: coverUrl,
      duration: musicPages.isNotEmpty
          ? Duration(seconds: int.tryParse(musicPages.first.duration) ?? 0)
          : null,
      audioUrl: '',
      pages: musicPages,
    );
  }

  /// 创建副本并更新分P信息
  SearchResult copyWithPages(List<Page> newPages) {
    return SearchResult(
      id: id,
      title: title,
      subtitle: subtitle,
      coverUrl: coverUrl,
      type: type,
      artist: artist,
      pages: newPages,
    );
  }

  /// 按类型过滤搜索结果。
  static List<SearchResult> filterByType(
    List<SearchResult> results,
    SearchResultType type,
  ) {
    return results.where((r) => r.type == type).toList();
  }

  /// 从结果集中提取所有出现过的类型（保持首次出现顺序）。
  static List<SearchResultType> getAvailableTypes(List<SearchResult> results) {
    final seen = <SearchResultType>{};
    final out = <SearchResultType>[];
    for (final r in results) {
      if (seen.add(r.type)) out.add(r.type);
    }
    return out;
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
