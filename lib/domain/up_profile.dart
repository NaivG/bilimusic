import 'package:bilimusic/domain/bili_following.dart';

/// 歌手页（UP 页）页头要展示的 UP 主资料。
///
/// 只留页头渲染用得上的字段：mid（投稿接口的入参）+ 头像 / 昵称 / 签名 / 认证说明。
class UpProfile {
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

  const UpProfile({
    required this.mid,
    required this.name,
    this.face = '',
    this.sign = '',
    this.verifyDesc = '',
  });

  /// 从关注列表条目取资料。
  ///
  /// 关注列表已经带齐页头要的四个字段，点进去时不必再单独查一次用户信息。
  factory UpProfile.fromFollowing(BiliFollowing following) => UpProfile(
    mid: following.mid,
    name: following.name,
    face: following.face,
    sign: following.sign,
    verifyDesc: following.verifyDesc,
  );

  /// 是否有官方认证（页头头像右下角的徽标）
  bool get isVerified => verifyDesc.isNotEmpty;

  /// 昵称兜底：接口偶尔不给 uname，此时用 mid 撑住页头。
  String get displayName => name.isNotEmpty ? name : 'mid $mid';

  /// 描述行文案：优先签名，其次认证说明，都没有时兜底。
  String get description {
    if (sign.isNotEmpty) return sign;
    if (verifyDesc.isNotEmpty) return verifyDesc;
    return '这个人很神秘，什么都没写';
  }
}
