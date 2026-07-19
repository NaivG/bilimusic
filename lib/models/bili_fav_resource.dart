/// 收藏夹资源分页结果。
class FavResourcePage {
  final List<FavResource> resources;
  final bool hasMore;
  final String title;
  final String cover;
  final int mediaCount;

  const FavResourcePage({
    required this.resources,
    required this.hasMore,
    this.title = '',
    this.cover = '',
    this.mediaCount = 0,
  });

  const FavResourcePage.empty()
    : resources = const [],
      hasMore = false,
      title = '',
      cover = '',
      mediaCount = 0;
}

/// 收藏夹资源引用（批量查询 `id:type` 用）。
class FavResourceRef {
  final int id;
  final int type;

  const FavResourceRef({required this.id, required this.type});
}

/// 收藏夹资源条目（对应 `/x/v3/fav/resource/list` 中 `medias[]` 的单条）。
///
/// 类型对照：
///   2  = 视频稿件（可用 bvid 播放）
///   12 = 音频稿件（部分有 bvid，可用 bvid 播放）
///   21 = 视频合集（跳过）
class FavResource {
  final int id;
  final int type;
  final String title;
  final String cover;
  final String intro;
  final int page;
  final int duration;
  final String bvid;
  final String upperName;
  final int attr; // 0=正常, 1/9=失效

  const FavResource({
    required this.id,
    required this.type,
    required this.title,
    this.cover = '',
    this.intro = '',
    this.page = 1,
    this.duration = 0,
    this.bvid = '',
    this.upperName = '',
    this.attr = 0,
  });

  /// 是否可用于播放（视频稿件或音频稿件，且未失效）。
  bool get isPlayable =>
      (type == 2 || type == 12) && (attr == 0) && bvid.isNotEmpty;

  factory FavResource.fromJson(Map<String, dynamic> json) {
    final upper = json['upper'];
    return FavResource(
      id: json['id'] is int ? json['id'] as int : 0,
      type: json['type'] is int ? json['type'] as int : 0,
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      intro: json['intro']?.toString() ?? '',
      page: json['page'] is int ? json['page'] as int : 1,
      duration: json['duration'] is int ? json['duration'] as int : 0,
      bvid: json['bvid']?.toString() ?? json['bv_id']?.toString() ?? '',
      upperName: upper is Map ? (upper['name']?.toString() ?? '') : '',
      attr: json['attr'] is int ? json['attr'] as int : 0,
    );
  }
}
