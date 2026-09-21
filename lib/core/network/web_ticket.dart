import 'dart:convert';

import 'package:crypto/crypto.dart';

/// bili_ticket：走 HMAC-SHA256 换取的 JWT 票据。
///
/// 该接口顺带返回 WBI 需要的 `nav.img` / `nav.sub`，所以引导阶段能省一次 nav 请求。
class WebTicket {
  const WebTicket({
    required this.ticket,
    required this.createdAt,
    required this.ttlSeconds,
    this.imgKey,
    this.subKey,
  });

  /// JWT 形式的票据本体。
  final String ticket;

  /// 签发时间（UNIX 秒）。
  final int createdAt;

  /// 有效秒数，实测 259200。
  final int ttlSeconds;

  /// 响应里 `data.nav.img` 解析出的 WBI img_key。
  final String? imgKey;

  /// 响应里 `data.nav.sub` 解析出的 WBI sub_key。
  final String? subKey;

  bool isExpiredAt(DateTime now) =>
      now.millisecondsSinceEpoch ~/ 1000 >= createdAt + ttlSeconds;

  /// 从接口响应体解析；结构不符时返回 null（票据只是"降低风控概率"，失败不该中断启动）。
  static WebTicket? tryParse(Object? decoded) {
    if (decoded is! Map) return null;
    if (decoded['code'] != 0) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    final ticket = data['ticket'];
    if (ticket is! String || ticket.isEmpty) return null;

    final nav = data['nav'];
    final img = nav is Map ? nav['img'] : null;
    final sub = nav is Map ? nav['sub'] : null;

    return WebTicket(
      ticket: ticket,
      createdAt: (data['created_at'] as num?)?.toInt() ?? 0,
      ttlSeconds: (data['ttl'] as num?)?.toInt() ?? 259200,
      imgKey: img is String ? wbiKeyFromUrl(img) : null,
      subKey: sub is String ? wbiKeyFromUrl(sub) : null,
    );
  }

  /// 从 WBI 图片 URL 里取出 key。
  ///
  /// 需要的是文件名去扩展名的部分。接口偶尔也会直接给裸 key，这里一并兼容。
  static String? wbiKeyFromUrl(String url) {
    if (url.isEmpty) return null;
    final slash = url.lastIndexOf('/');
    final filename = slash == -1 ? url : url.substring(slash + 1);
    final dot = filename.indexOf('.');
    final key = dot == -1 ? filename : filename.substring(0, dot);
    return key.isEmpty ? null : key;
  }

  /// 计算 `hexsign`。
  ///
  /// 独立成静态方法是为了能直接用固定时间戳做单元测试。
  static String hexSign(int ts, {String key = 'XgwSnGZ1p'}) {
    final mac = Hmac(sha256, utf8.encode(key));
    return mac.convert(utf8.encode('ts$ts')).toString();
  }
}
