import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/shared/utils/title_meta_filter.dart';

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

  /// 创作者（UP 主）：mid + 昵称 + 头像。
  ///
  /// 昵称是列表/播放页直接显示的那一份（用 `artist.displayName` 取）；
  /// mid 是歌手页的入参，缺失时由 `ApiService.ensureMid` 按需补齐。
  final Artist artist;

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
      artist: _artistFromJson(json),
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
      'artist': artist.toJson(),
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
  ///
  /// 标题过 [TitleMetaFilter.maybeClean]：设置开启时清掉【MV】【中字】
  /// 这类元信息，关闭时原样返回（实验性，见 title_meta_filter.dart）。
  factory Music.fromArchiveJson(Map<String, dynamic> json) {
    final cover = (json['pic'] ?? json['cover']) as String? ?? '';
    return Music(
      id: (json['bvid'] as String?) ?? json['aid']?.toString() ?? '',
      title: TitleMetaFilter.maybeClean(json['title'] as String? ?? ''),
      artist: _artistFromCard(json),
      album: json['tname'] as String? ?? '未知专辑',
      coverUrl: cover.isNotEmpty ? '$cover$biliCoverThumbSuffix' : '',
      duration: json['duration'] is int
          ? Duration(seconds: json['duration'] as int)
          : null,
      audioUrl: '',
    );
  }

  /// 从 B 站「UP 主投稿明细」条目构造（`space/wbi/arc/search` 的 `vlist`）。
  ///
  /// 与 [Music.fromArchiveJson] 有两处不同：
  ///   - 时长的字段名是 `length`，值是 `MM:SS` / `H:MM:SS` **文本**，
  ///     不是 `duration` 整数秒；
  ///   - 条目里没有分区名 `tname`，[album] 由调用方传来源名
  ///     （如「某某的投稿」）充当列表副标题的第二段。
  ///
  /// 与收藏夹导入一样不填 cid。
  factory Music.fromSpaceArcJson(
    Map<String, dynamic> json, {
    String album = '',
  }) {
    final cover = json['pic']?.toString() ?? '';
    return Music(
      id: json['bvid']?.toString() ?? '',
      title: TitleMetaFilter.maybeClean(json['title'] as String? ?? ''),
      artist: Artist.fromFlat(json, faceKey: 'face'),
      album: album,
      coverUrl: cover.isNotEmpty ? '$cover$biliCoverThumbSuffix' : '',
      duration: _parseLength(json['length']?.toString()),
      audioUrl: '',
    );
  }

  /// 是否为系列（多P）视频
  bool get isSeries => pages.length > 1;

  /// 队列 / 收藏域的唯一标识（bvid + 分P cid）。
  /// 注意与 [uniqueKey] 不同：那个支持精确到分P对象，这个是 (id, cid) 判等键。
  String get key => '${id}_$cid';

  /// 是否与 [other] 指向同一首曲目。
  ///
  /// cid 异步补齐，入列时可能是空串，拿到详情后才知道具体分P。
  /// 判等时把空 cid 当作通配符，否则同一首歌会以 `(bvid, "")` 和 `(bvid, cid)`
  /// 两份进入队列，回填后撞成同一个 [key]。
  bool sameTrackAs(Music other) =>
      id == other.id && (cid.isEmpty || other.cid.isEmpty || cid == other.cid);

  /// 「artist - album」副标题行（列表项通用，分隔符统一为 ` - `）。
  String get subtitleText => '${artist.displayName} - $album';

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
    Artist? artist,
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

/// 解析落盘/传输 JSON 里的 `artist`。
///
/// 老数据（≤1.10.x）存的是昵称字符串，mid / 头像另在两个平铺字段里；
/// 两种形状都认，缺的补空值。**只有读侧兼容，写侧统一是对象**。
Artist _artistFromJson(Map<String, dynamic> json) {
  final raw = json['artist'];
  if (raw is Map) {
    return Artist(
      mid: (raw['mid'] as num?)?.toInt() ?? 0,
      name: raw['name']?.toString() ?? '',
      face: raw['face']?.toString() ?? '',
    );
  }
  return Artist(
    mid: (json['ownerMid'] as num?)?.toInt() ?? 0,
    name: raw?.toString() ?? '',
    face: json['ownerFace']?.toString() ?? '',
  );
}

/// 解析稿件卡片 JSON 的创作者：优先 `owner` 对象，退回扁平的 `author` / `mid` / `upic`。
Artist _artistFromCard(Map<String, dynamic> json) {
  final owner = json['owner'];
  if (owner is Map) return Artist.fromOwner(owner);

  final author = json['author'];
  final name = author is Map
      ? author['name']?.toString() ?? ''
      : author?.toString() ?? '';
  return Artist(
    mid: int.tryParse(json['mid']?.toString() ?? '') ?? 0,
    name: name,
    face: normalizeFaceUrl(json['upic']),
  );
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

/// 解析 B 站列表接口里的 `MM:SS` / `H:MM:SS` 时长文本。
///
/// 只认 `:` 分隔的 2~3 段数字，其余（空串、`--:--`、纯数字）一律返回 null——
/// 猜错时长会让列表显示一个凭空的进度，宁可不显示。
Duration? _parseLength(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) return null;

  var seconds = 0;
  for (final part in parts) {
    final value = int.tryParse(part.trim());
    if (value == null || value < 0) return null;
    seconds = seconds * 60 + value;
  }
  return Duration(seconds: seconds);
}
