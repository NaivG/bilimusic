/// Bilibili 关注列表里的一个 UP 主。
///
/// 对应 `/x/relation/followings` 返回的 `data.list` 条目（文档里的「关系列表对象」）。
/// 只留浏览关注列表用得上的字段：接口还回了 `contract_info` / `nameplate` /
/// `pendant` 这类挂件与契约信息，本项目不渲染它们，就没有建模。
class BiliFollowing {
  /// 用户 mid
  final int mid;

  /// 昵称
  final String name;

  /// 头像 URL
  final String face;

  /// 个性签名
  final String sign;

  /// 认证说明（`official_verify.desc`，未认证为空串）
  final String verifyDesc;

  /// 是否大会员（`vip.vipStatus == 1`）
  final bool isVip;

  /// 我关注 TA 的时间（秒级时间戳，接口没给出时为 0）
  ///
  /// 语义来自 `mtime`：文档里它是「对方关注目标用户的时间」，而这里的
  /// 目标用户就是自己，所以在自己的关注列表上它恰好等于「我关注 TA 的时间」。
  final int followTime;

  const BiliFollowing({
    required this.mid,
    required this.name,
    this.face = '',
    this.sign = '',
    this.verifyDesc = '',
    this.isVip = false,
    this.followTime = 0,
  });

  factory BiliFollowing.fromJson(Map<String, dynamic> json) {
    final official = json['official_verify'];
    final vip = json['vip'];
    return BiliFollowing(
      mid: _asInt(json['mid']),
      name: json['uname']?.toString() ?? '',
      face: json['face']?.toString() ?? '',
      sign: json['sign']?.toString() ?? '',
      verifyDesc: official is Map ? (official['desc']?.toString() ?? '') : '',
      isVip: vip is Map && _asInt(vip['vipStatus']) == 1,
      followTime: _asInt(json['mtime']),
    );
  }

  /// 是否有官方认证（用于列表上的小徽标）
  bool get isVerified => verifyDesc.isNotEmpty;

  /// 关注时间；接口没给时返回 null。
  DateTime? get followedAt => followTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(followTime * 1000)
      : null;

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
