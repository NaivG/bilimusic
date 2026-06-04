/// 用户信息模型
/// 从 B 站 /x/web-interface/nav 接口解析的核心用户数据
class UserInfo {
  /// 用户 mid
  final String uid;

  /// 用户名
  final String userName;

  /// 头像 URL
  final String avatar;

  /// 等级 [0, 7]
  final int level;

  /// 是否认证（大会员等信息）
  final bool isVip;

  /// 获取此信息的时间戳（毫秒）
  final int cachedAt;

  const UserInfo({
    required this.uid,
    required this.userName,
    required this.avatar,
    this.level = 0,
    this.isVip = false,
    this.cachedAt = 0,
  });

  /// 从 /x/web-interface/nav 的 data 字段构造
  factory UserInfo.fromNavData(Map<String, dynamic> data) {
    final member = data['member'] ?? data;
    final levelInfo = data['level_info'] ?? {};
    final vipInfo = data['vip'] ?? {};

    return UserInfo(
      uid: (data['mid'] ?? member['mid'] ?? '').toString(),
      userName: data['uname'] ?? member['uname'] ?? '',
      avatar: data['face'] ?? member['face'] ?? '',
      level: levelInfo['current_level'] ?? 0,
      isVip: vipInfo['status'] == 1,
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 从持久化 JSON 恢复
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      uid: json['uid']?.toString() ?? '',
      userName: json['userName'] ?? '',
      avatar: json['avatar'] ?? '',
      level: json['level'] ?? 0,
      isVip: json['isVip'] ?? false,
      cachedAt: json['cachedAt'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'userName': userName,
        'avatar': avatar,
        'level': level,
        'isVip': isVip,
        'cachedAt': cachedAt,
      };

  /// 是否为空（未登录 / 无数据）
  bool get isEmpty => uid.isEmpty || userName.isEmpty;

  /// 缓存存活时长（毫秒）
  int get age => DateTime.now().millisecondsSinceEpoch - cachedAt;
}
