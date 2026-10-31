/// 一位创作者（B 站语境下的 UP 主）。
///
/// 三个字段对应 B 站各端点的两种写法，解析时统一收敛到这里：
///   - 对象写法：`view` 的 `data.owner`、`archive/related` / `region/feed/rcmd`
///     的 `owner`，键名就是 `mid` / `name` / `face`；
///   - 扁平写法：`search/all/v2` 的 `author` / `mid` / `upic`、
///     `space/wbi/arc/search` 的 `vlist[].author` / `mid` / `face`。
///
/// 大会员、认证、签名这类资料**不在这里**：它们只有用户信息与关注列表端点给，
/// 由关注列表条目与歌手页页头各自的模型持有。
class Artist {
  /// 用户 mid，0 表示来源没给（如本地旧数据、非稿件来源的本地曲目）。
  final int mid;

  /// 昵称。接口偶尔不给，读的时候用 [displayName]。
  final String name;

  /// 头像 URL，缺失时为空串。
  final String face;

  const Artist({this.mid = 0, this.name = '', this.face = ''});

  /// 从 `owner` 风格的对象构造（`view` / `archive/related` / 关注列表等）。
  factory Artist.fromOwner(Map<dynamic, dynamic> owner) => Artist(
    mid: parseMid(owner['mid']),
    name: owner['name']?.toString() ?? '',
    face: owner['face']?.toString() ?? '',
  );

  /// 从扁平写法构造。
  ///
  /// [nameKey] 是昵称所在的键（视频搜索 `author`、用户搜索 `uname`），
  /// [faceKey] 是头像所在的键（搜索 `upic`、空间投稿 `face`）。
  factory Artist.fromFlat(
    Map<String, dynamic> json, {
    String nameKey = 'author',
    String faceKey = 'upic',
  }) => Artist(
    mid: parseMid(json['mid']),
    name: json[nameKey]?.toString() ?? '',
    face: normalizeFaceUrl(json[faceKey]),
  );

  Map<String, dynamic> toJson() => {'mid': mid, 'name': name, 'face': face};

  /// 是否有足够信息跳转到歌手页（页头还要昵称/头像，mid 是接口入参）。
  bool get hasMid => mid > 0;

  /// 页面上的昵称：接口没给（含只给空白）时兜一个通用称呼。
  String get displayName => name.trim().isNotEmpty ? name : '未知艺术家';

  @override
  String toString() => 'Artist($mid, $name)';

  /// 把接口里的 mid（int / num / 数字字符串）收敛成 int，认不出就是 0。
  static int parseMid(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// 头像 URL 归一化：图片域会回协议相对的 `//i1.hdslb.com/...`。
///
/// 列表端点（尤其搜索）给的就是这种形状，`Uri.parse` 认不出它，直接塞给
/// 图片组件会炸。空串原样返回，其余（含 `http://`）不拦——与封面同一套宽松口径。
String normalizeFaceUrl(Object? raw) {
  final url = raw?.toString().trim() ?? '';
  if (url.startsWith('//')) return 'https:$url';
  return url;
}
