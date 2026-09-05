/// 音乐渲染样式枚举
enum MusicRenderStyle {
  /// 卡片样式 - 响应式卡片（Mobile/Tablet/Desktop自适应）
  card,

  /// 叠加卡片样式 - 卡片右下角显示"+xxx"表示分P数量
  stacked,

  /// 列表样式 - 类似PlaylistItem的水平列表
  list,
}

/// B 站封面 CDN 缩略后缀：列表封面统一按此规格取图，省流量。
const biliCoverThumbSuffix = '@672w_378h';

/// 封面缺失 / 非法时的 fallback 占位图（唯一来源，勿再内联 URL 字面量）。
const fallbackCoverUrl =
    'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png';

class Music {
  final String id; // bvid
  final String cid; // 分P cid，音视频请求需要
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final Duration? duration;
  final String audioUrl;
  final List<Page> pages; // ⚠️ 已废弃，请使用 BiliItem.pages
  final bool isFavorite;

  /// 当前分P索引（用于多P视频）
  final int currentPageIndex;

  /// 渲染样式
  final MusicRenderStyle renderStyle;

  Music({
    required this.id,
    this.cid = '', // 分P cid
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.duration,
    required this.audioUrl,
    this.pages = const [], // ⚠️ 已废弃，请使用 BiliItem.pages
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
          ? fallbackCoverUrl
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

  /// 从 B 站稿件卡片 JSON 构造（`archive/related`、`region/feed/rcmd`
  /// 等列表端点共用）。
  ///
  /// 完整详情（含分P列表）的 view 端点请走 `BiliItem.fromViewApi`：
  /// 它逐分P构造（cid/title/duration 来自 pages 数组），album 语义为
  /// 视频标题，与稿件卡片（分区名）不同，属有意区分。
  factory Music.fromArchiveJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    final author = json['author'];
    final ownerName = owner is Map ? owner['name'] as String? : null;
    final authorName = author is Map ? author['name'] as String? : null;
    final cover = (json['pic'] ?? json['cover']) as String? ?? '';
    return Music(
      id: (json['bvid'] as String?) ?? json['aid']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      artist: authorName ?? ownerName ?? '未知艺术家',
      album: json['tname'] as String? ?? '未知专辑',
      coverUrl: cover.isNotEmpty ? '$cover$biliCoverThumbSuffix' : '',
      duration: json['duration'] is int
          ? Duration(seconds: json['duration'] as int)
          : null,
      audioUrl: '',
    );
  }

  /// 是否为系列（多P）视频
  bool get isSeries => pages.length > 1;

  /// 队列 / 收藏域的唯一标识（bvid + 分P cid）。
  /// 注意与 [uniqueKey] 不同：那个支持精确到分P对象，这个是 (id, cid) 判等键。
  String get key => '${id}_$cid';

  /// 「artist - album」副标题行（列表项通用，分隔符统一为 ` - `）。
  String get subtitleText => '$artist - $album';

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

  String get safeCoverUrl =>
      isValidImageUrl(coverUrl) ? coverUrl : fallbackCoverUrl;
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
