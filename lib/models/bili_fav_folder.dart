/// Bilibili 收藏夹元数据
/// 对应 API /x/v3/fav/folder/created/list-all 和 /collected/list 的返回结构
class BiliFavFolder {
  /// 收藏夹完整 ID（media_id）
  final int mediaId;

  /// 收藏夹原始 ID
  final int fid;

  /// 创建者 mid
  final int mid;

  /// 收藏夹标题
  final String title;

  /// 封面 URL
  final String cover;

  /// 创建者昵称
  final String upperName;

  /// 内容数量
  final int mediaCount;

  /// 简介
  final String intro;

  /// 属性位（0位：0=公开，1=私有；1位：0=默认收藏夹，1=其他）
  final int attr;

  /// 收藏夹来源类型
  final BiliFavFolderType folderType;

  const BiliFavFolder({
    required this.mediaId,
    required this.fid,
    required this.mid,
    required this.title,
    this.cover = '',
    this.upperName = '',
    this.mediaCount = 0,
    this.intro = '',
    this.attr = 0,
    this.folderType = BiliFavFolderType.created,
  });

  /// 是否公开
  bool get isPublic => (attr & 1) == 0;

  /// 是否为默认收藏夹
  bool get isDefaultFolder => (attr & 2) == 0;

  /// 从 created/list-all API 返回的 list 条目构造
  factory BiliFavFolder.fromCreatedList(Map<String, dynamic> json) {
    return BiliFavFolder(
      mediaId: json['id'] ?? 0,
      fid: json['fid'] ?? 0,
      mid: json['mid'] ?? 0,
      title: json['title'] ?? '',
      mediaCount: json['media_count'] ?? 0,
      attr: json['attr'] ?? 0,
      folderType: BiliFavFolderType.created,
    );
  }

  /// 从 collected/list API 返回的 list 条目构造
  factory BiliFavFolder.fromCollectedList(Map<String, dynamic> json) {
    final upper = json['upper'] ?? {};
    return BiliFavFolder(
      mediaId: json['id'] ?? 0,
      fid: json['fid'] ?? 0,
      mid: json['mid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      upperName: upper['name'] ?? '',
      mediaCount: json['media_count'] ?? 0,
      intro: json['intro'] ?? '',
      attr: json['attr'] ?? 0,
      folderType: BiliFavFolderType.collected,
    );
  }

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'fid': fid,
        'mid': mid,
        'title': title,
        'cover': cover,
        'upperName': upperName,
        'mediaCount': mediaCount,
        'intro': intro,
        'attr': attr,
        'folderType': folderType.name,
      };

  factory BiliFavFolder.fromJson(Map<String, dynamic> json) {
    return BiliFavFolder(
      mediaId: json['mediaId'] ?? 0,
      fid: json['fid'] ?? 0,
      mid: json['mid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      upperName: json['upperName'] ?? '',
      mediaCount: json['mediaCount'] ?? 0,
      intro: json['intro'] ?? '',
      attr: json['attr'] ?? 0,
      folderType: BiliFavFolderType.values.firstWhere(
        (e) => e.name == json['folderType'],
        orElse: () => BiliFavFolderType.created,
      ),
    );
  }
}

/// 收藏夹来源类型
enum BiliFavFolderType {
  created, // 创建的收藏夹
  collected, // 收藏的收藏夹
}
