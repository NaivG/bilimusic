import 'dart:convert';

import 'package:crypto/crypto.dart';

/// WBI 签名所需的实时口令。
///
/// 来自 nav 接口的 `data.wbi_img.img_url` / `sub_url`（文件名去扩展名），
/// 或 GenWebTicket 的 `data.nav.img` / `sub`。全站通用，**每日更替**。
class WbiKeys {
  const WbiKeys({
    required this.imgKey,
    required this.subKey,
    required this.mixinKey,
    required this.fetchedAt,
  });

  final String imgKey;
  final String subKey;

  /// `imgKey + subKey` 经重排表打乱后截取前 32 位。
  final String mixinKey;

  final DateTime fetchedAt;

  static WbiKeys fromKeys(
    String imgKey,
    String subKey, {
    required DateTime fetchedAt,
  }) => WbiKeys(
    imgKey: imgKey,
    subKey: subKey,
    mixinKey: WbiSigner.mixinKeyOf(imgKey, subKey),
    fetchedAt: fetchedAt,
  );

  @override
  String toString() => 'WbiKeys(imgKey: $imgKey, subKey: $subKey)';
}

/// WBI 签名器。
///
/// 签名是**部分接口**的要求，且真正的门槛往往在风控而不是签名本身，
/// 所以这里做成**按需签名**，而不是给每个请求都摊一次 md5 + 口令刷新：
///   - 默认不签，调用方显式 `signed: true` 才签；
///   - `BiliClient` 在撞上风控（`-352` / `-412` / HTTP 412）且当次没签名时，
///     会自动刷新口令并补签重试一次。
class WbiSigner {
  WbiSigner({
    required this.fetchKeys,
    this.ttl = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 口令获取方式（通常走 nav 或 GenWebTicket 接口）。
  final Future<WbiKeys> Function() fetchKeys;

  /// 本地缓存时长。口令每日更替，默认 6 小时足够保守。
  final Duration ttl;

  final DateTime Function() _clock;

  WbiKeys? _cached;
  Future<WbiKeys>? _inflight;

  /// 重排映射表，长度 64。
  static const List<int> mixinKeyEncTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, //
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  /// 拿口令。命中缓存直接返回；并发调用共享同一次请求。
  Future<WbiKeys> keys({bool force = false}) {
    final cached = _cached;
    if (!force &&
        cached != null &&
        _clock().difference(cached.fetchedAt) < ttl) {
      return Future.value(cached);
    }
    final pending = _inflight;
    if (pending != null) return pending;
    final future = _load();
    _inflight = future;
    return future;
  }

  Future<WbiKeys> _load() async {
    try {
      final keys = await fetchKeys();
      _cached = keys;
      return keys;
    } finally {
      _inflight = null;
    }
  }

  /// 丢弃缓存（签到风控、口令过期时调用）。
  void invalidate() => _cached = null;

  /// 给参数签名，返回可直接拼进 URL 的 query。
  ///
  /// 结果形如 `bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f...`：
  /// 参数按键名升序、`wts` 参与排序、`w_rid` 追加在末尾。
  Future<String> signQuery(
    Map<String, Object?> params, {
    bool forceRefreshKeys = false,
  }) async {
    final resolved = await keys(force: forceRefreshKeys);
    return signWithKeys(
      params,
      mixinKey: resolved.mixinKey,
      wts: unixSeconds(),
    );
  }

  /// 当前时间戳（秒），抽出来方便测试注入。
  int unixSeconds() => _clock().millisecondsSinceEpoch ~/ 1000;

  /// 用指定 mixin_key 与时间戳签名，纯函数，便于对照官方测试向量。
  static String signWithKeys(
    Map<String, Object?> params, {
    required String mixinKey,
    required int wts,
  }) {
    final query = buildQuery(params, wts: wts);
    return '$query&w_rid=${sign(query, mixinKey)}';
  }

  /// 构造待签名的 query（不含 `w_rid`）。
  static String buildQuery(Map<String, Object?> params, {required int wts}) {
    final merged = <String, String>{};
    params.forEach((key, value) {
      if (value == null) return;
      merged[key] = stringify(value);
    });
    merged['wts'] = '$wts';

    final sortedKeys = merged.keys.toList()..sort();
    return sortedKeys
        .map(
          (key) =>
              '${Uri.encodeComponent(key)}='
              '${Uri.encodeComponent(filterReserved(merged[key]!))}',
        )
        .join('&');
  }

  /// `md5(query + mixin_key)`，小写十六进制。
  static String sign(String query, String mixinKey) =>
      md5.convert(utf8.encode('$query$mixinKey')).toString();

  /// `imgKey + subKey` 按重排表打乱后取前 32 位。
  ///
  /// 重排表最长取到下标 63，所以两个 key 拼起来必须够 64 位；
  /// 长度不对说明口令没取全（服务端结构变了 / 解析错了），直接报清楚。
  static String mixinKeyOf(String imgKey, String subKey) {
    final raw = '$imgKey$subKey';
    if (raw.length < 64) {
      throw ArgumentError.value(
        raw,
        'imgKey+subKey',
        'WBI 口令长度不足 64（imgKey=${imgKey.length}, subKey=${subKey.length}）',
      );
    }
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(raw[mixinKeyEncTab[i]]);
    }
    return buffer.toString();
  }

  /// 值里的 `!'()*` 要在编码前剔除（否则签名不一致）。
  static String filterReserved(String value) =>
      value.replaceAll(RegExp(r"[!'()*]"), '');

  /// 与 JS `String(value)` 对齐：整数值的 double 不能写成 `1.0`。
  static String stringify(Object value) {
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}
