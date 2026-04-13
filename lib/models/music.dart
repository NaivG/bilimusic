import 'package:bilimusic/utils/network_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 音乐渲染样式枚举
enum MusicRenderStyle {
  /// 卡片样式 - 响应式卡片（Mobile/Tablet/Desktop自适应）
  card,

  /// 叠加卡片样式 - 卡片右下角显示"+xxx"表示分P数量
  stacked,

  /// 列表样式 - 类似PlaylistItem的水平列表
  list,
}

class Music {
  final String id;   // bvid
  final String cid;  // 分P cid，音视频请求需要
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final Duration? duration;
  final String audioUrl;
  final List<Page> pages;  // ⚠️ 已废弃，请使用 BiliItem.pages
  final bool isFavorite;

  /// 当前分P索引（用于多P视频）
  final int currentPageIndex;

  /// 渲染样式
  final MusicRenderStyle renderStyle;

  Music({
    required this.id,
    this.cid = '',  // 分P cid
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.duration,
    required this.audioUrl,
    this.pages = const [],  // ⚠️ 已废弃，请使用 BiliItem.pages
    this.isFavorite = false,
    this.currentPageIndex = 0,
    this.renderStyle = MusicRenderStyle.card,
  });

  factory Music.fromJson(Map<String, dynamic> json) {
    List<Page> pagesList = [];
    if (json['pages'] != null) {
      var list = json['pages'] as List;
      pagesList = list.map((i) => Page.fromJson(i)).toList();
    }

    return Music(
      id: json['id'] ?? '',
      cid: json['cid'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album']?.toString() ?? '未知专辑',
      coverUrl: json['coverUrl']?.toString().trim().isEmpty ?? true
          ? 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png'
          : json['coverUrl'],
      duration: json['duration'] != null
          ? Duration(seconds: int.parse(json['duration']))
          : null,
      audioUrl: json['audioUrl']?.toString() ?? '',
      pages: pagesList,
      isFavorite: json['isFavorite'] ?? false,
      currentPageIndex: json['currentPageIndex'] ?? 0,
      renderStyle: json['renderStyle'] != null
          ? MusicRenderStyle.values.firstWhere(
              (e) => e.name == json['renderStyle'],
              orElse: () => MusicRenderStyle.card,
            )
          : MusicRenderStyle.card,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cid': cid,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'duration': duration?.inSeconds.toString() ?? '300',
      'audioUrl': audioUrl,
      'pages': pages.map((page) => page.toJson()).toList(),
      'isFavorite': isFavorite,
      'currentPageIndex': currentPageIndex,
      'renderStyle': renderStyle.name,
    };
  }

  /// 获取视频详情
  Future<Music> getVideoDetails() async {
    // 如果已经有持续时间，不需要重新获取
    if (duration != null && duration!.inSeconds > 0) {
      return Music(
        id: id,
        cid: cid,
        title: title,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        duration: duration,
        audioUrl: audioUrl,
        pages: pages,
        isFavorite: isFavorite,
        currentPageIndex: currentPageIndex,
        renderStyle: renderStyle,
      );
    }

    // 否则从网络获取详细信息
    final response = await http.get(
      Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$id'),
      headers: NetworkConfig.biliHeaders,
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['code'] == 0) {
        final data = json['data'];
        final pagesData = data['pages'] ?? [];
        final pagesList = pagesData
            .map<Page>(
              (pageJson) => Page.fromJson(
                pageJson,
                pageIndex: pagesData.indexOf(pageJson),
              ),
            )
            .toList();

        // 更新duration为第一个分P的时长
        final newDuration = pagesList.isNotEmpty
            ? Duration(seconds: int.parse(pagesList[0].duration))
            : const Duration(seconds: 180);

        // 获取当前分P的 cid
        String pageCid;
        if (pages.isNotEmpty && currentPageIndex < pages.length) {
          pageCid = pages[currentPageIndex].cid;
        } else if (pagesList.isNotEmpty) {
          pageCid = pagesList[0].cid;
        } else {
          pageCid = data['cid']?.toString() ?? '';
        }

        return Music(
          id: id,
          cid: pageCid,
          title: title.isEmpty ? data['title'] : title,
          artist: artist.isEmpty ? data['owner']['name'] : artist,
          album: album.isEmpty ? (data['album'] ?? '未知专辑') : album,
          coverUrl: coverUrl.isEmpty ? data['pic'] + "@672w_378h" : coverUrl,
          duration: newDuration,
          audioUrl: audioUrl,
          pages: pagesList,
          isFavorite: isFavorite,
          currentPageIndex: currentPageIndex,
          renderStyle: renderStyle,
        );
      }
    }
    return this; // 如果获取失败保持原样
  }

  /// 是否为系列（多P）视频
  bool get isSeries => pages.length > 1;

  /// 获取当前分P
  Page? get currentPage {
    if (pages.isEmpty || currentPageIndex >= pages.length) return null;
    return pages[currentPageIndex];
  }

  /// 获取唯一标识（支持精确到分P）
  String get uniqueKey {
    final page = currentPage;
    return page != null ? '${id}_${page.cid}' : id;
  }

  /// 创建副本并更新指定字段
  Music copyWith({
    String? cid,
    bool? isFavorite,
    int? currentPageIndex,
    MusicRenderStyle? renderStyle,
    List<Page>? pages,
    String? audioUrl,
    Duration? duration,
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
  }) {
    return Music(
      id: id,
      cid: cid ?? this.cid,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: duration ?? this.duration,
      audioUrl: audioUrl ?? this.audioUrl,
      pages: pages ?? this.pages,
      isFavorite: isFavorite ?? this.isFavorite,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      renderStyle: renderStyle ?? this.renderStyle,
    );
  }

  /// 更新音频URL（用于分P切换后更新URL）
  Music withAudioUrl(String url) {
    return copyWith(audioUrl: url);
  }

  /// 更新收藏状态
  Music withFavorite(bool favorite) {
    return copyWith(isFavorite: favorite);
  }

  static bool isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    return Uri.tryParse(url)?.hasAbsolutePath == true;
  }

  String get safeCoverUrl => isValidImageUrl(coverUrl)
      ? coverUrl
      : 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png';
}

class Page {
  final String cid;
  final String duration;
  final String part;

  /// 分P序号（从0开始）
  final int pageIndex;

  /// 视频来源: vupload/hunan/qq/bilibili
  final String? from;

  /// 视频宽度
  final int? width;

  /// 视频高度
  final int? height;

  /// 是否旋转（1=旋转）
  final int? rotate;

  /// 缓存的音频URL（延迟加载，非持久化）
  String? cachedAudioUrl;

  Page({
    required this.cid,
    required this.duration,
    required this.part,
    this.pageIndex = 0,
    this.from,
    this.width,
    this.height,
    this.rotate,
    this.cachedAudioUrl,
  });

  factory Page.fromJson(Map<String, dynamic> json, {int? pageIndex}) {
    final dimension = json['dimension'];
    return Page(
      cid: json['cid'].toString(),
      duration: json['duration'].toString(),
      part: json['part'] ?? json['title'] ?? '',
      pageIndex: pageIndex ?? json['page'] ?? 0,
      from: json['from'],
      width: dimension?['width'],
      height: dimension?['height'],
      rotate: dimension?['rotate'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cid': cid,
      'duration': duration,
      'part': part,
      'page': pageIndex,
      'from': from,
      'dimension': {'width': width, 'height': height, 'rotate': rotate},
    };
  }

  /// 获取分P时长 (Duration类型)
  Duration get durationValue => Duration(seconds: int.tryParse(duration) ?? 0);

  /// 格式化时长字符串 MM:SS
  String get formattedDuration {
    final d = durationValue;
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  /// 获取分辨率字符串
  String? get resolution {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return null;
  }

  /// 获取完整标识符 (cid)
  String get uniqueId => cid;

  /// 创建副本
  Page copyWith({
    String? cid,
    String? duration,
    String? part,
    int? pageIndex,
    String? from,
    int? width,
    int? height,
    int? rotate,
    String? cachedAudioUrl,
  }) {
    return Page(
      cid: cid ?? this.cid,
      duration: duration ?? this.duration,
      part: part ?? this.part,
      pageIndex: pageIndex ?? this.pageIndex,
      from: from ?? this.from,
      width: width ?? this.width,
      height: height ?? this.height,
      rotate: rotate ?? this.rotate,
      cachedAudioUrl: cachedAudioUrl ?? this.cachedAudioUrl,
    );
  }
}
