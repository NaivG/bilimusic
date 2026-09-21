import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/device_identity.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/network/wbi.dart';
import 'package:bilimusic/core/network/web_ticket.dart';

/// 用裸 `http.Client` 完成启动阶段的自举请求。
///
/// 这些请求发生在"还没有可用客户端"的时候（需要先有 Cookie 才能正常调接口），
/// 所以不复用 `BiliClient`，避免循环依赖；同时它拿到的 `Set-Cookie` 会写回 [jar]，
/// 后续所有请求都受益。
///
/// 设备的 Cookie 需要准备：
/// `buvid3` / `buvid4`（finger/spi 下发）、`b_nut`（下发时刻时间戳）、
/// `bili_ticket`（HMAC 换取的 JWT），外加 `_uuid` / `b_lsid` 两个 Web 端标识。
class BiliBootstrap {
  BiliBootstrap({
    required this.jar,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _httpClient = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final CookieJar jar;
  final Duration timeout;
  final http.Client _httpClient;
  final DateTime Function() _clock;

  /// 最近一次自举失败的原因（自举失败不阻断启动，只记录）。
  Object? lastError;

  WbiKeys? _ticketKeys;

  /// 是否已经拿到 buvid3 / buvid4。
  bool get hasDeviceIdentity =>
      jar.contains('buvid3') && jar.contains('buvid4');

  /// 是否已有有效的 bili_ticket。
  bool get hasTicket {
    if (!jar.contains('bili_ticket')) return false;
    final expires = int.tryParse(jar.value('bili_ticket_expires') ?? '');
    if (expires == null) return false;
    return _clock().millisecondsSinceEpoch ~/ 1000 < expires;
  }

  /// 准备设备标识与票据。幂等，已经齐了就只做本地补齐。
  Future<void> ensureDeviceCookies() async {
    try {
      _ensureLocalIdentity();
      if (!hasDeviceIdentity) await _fetchBuvids();
      if (!hasTicket) await _fetchTicket();
      // 拿完 buvid3/4 激活。
      // 没激活直接调 `/x/web-interface/wbi/search/type` 会拿到 gaia 风控的
      // 「code=0 + data 只有 v_voucher」伪成功形态，被客户端当 0 条结果返回。
      await _activateBuvid();
    } catch (error, stack) {
      lastError = error;
      // 自举失败不该让 App 起不来：缺 Cookie 也能跑，只是更容易撞风控。
      assert(() {
        // ignore: avoid_print
        print('BiliBootstrap.ensureDeviceCookies failed: $error\n$stack');
        return true;
      }());
    }
  }

  /// 本地就能生成的标识，缺失即补。
  void _ensureLocalIdentity() {
    final now = _clock();
    if (!jar.contains('_uuid')) {
      jar.set('_uuid', DeviceIdentity.uuid(), expiresAt: _inAYear(now));
    }
    if (!jar.contains('b_lsid')) {
      jar.set(
        'b_lsid',
        DeviceIdentity.bLsid(now: now),
        expiresAt: _inAYear(now),
      );
    }
    if (!jar.contains('b_nut')) {
      jar.set(
        'b_nut',
        '${DeviceIdentity.unixSeconds(now: now)}',
        expiresAt: _inAYear(now),
      );
    }
  }

  /// `/x/frontend/finger/spi` 下发 buvid3 / buvid4。
  Future<void> _fetchBuvids() async {
    final uri = Uri.parse('${NetworkConfig.apiBase}/x/frontend/finger/spi');
    final response = await _httpClient
        .get(uri, headers: NetworkConfig.baseHeaders(forUri: uri))
        .timeout(timeout);

    jar.ingest(uri, _setCookieValues(response));

    final decoded = _decode(response);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) {
      throw StateError('finger/spi 返回结构异常: ${_snippet(response)}');
    }
    final buvid3 = data['b_3'];
    final buvid4 = data['b_4'];
    if (buvid3 is! String || buvid4 is! String) {
      throw StateError('finger/spi 缺少 b_3 / b_4: ${_snippet(response)}');
    }
    final expires = _inAYear(_clock());
    jar.set('buvid3', buvid3, expiresAt: expires);
    jar.set('buvid4', buvid4, expiresAt: expires);
  }

  /// GenWebTicket：用 HMAC-SHA256 换 bili_ticket，顺带拿到 WBI 口令。
  Future<void> _fetchTicket() async {
    final ts = DeviceIdentity.unixSeconds(now: _clock());
    final csrf = jar.csrf ?? '';
    final uri = Uri.parse(
      '${NetworkConfig.apiBase}'
      '/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket'
      '?key_id=ec02'
      '&hexsign=${WebTicket.hexSign(ts)}'
      '&context%5Bts%5D=$ts'
      '&csrf=$csrf',
    );

    final response = await _httpClient
        .post(
          uri,
          headers: NetworkConfig.baseHeaders(forUri: uri, withOrigin: true),
        )
        .timeout(timeout);

    jar.ingest(uri, _setCookieValues(response));

    final ticket = WebTicket.tryParse(_decode(response));
    if (ticket == null) {
      throw StateError('GenWebTicket 未返回 ticket: ${_snippet(response)}');
    }

    final now = _clock();
    jar.set(
      'bili_ticket',
      ticket.ticket,
      expiresAt: now.add(Duration(seconds: ticket.ttlSeconds)),
    );
    // Web 端会同时种下过期时间戳，这里保持一致，便于下次启动判断是否要续。
    jar.set(
      'bili_ticket_expires',
      '${ticket.createdAt + ticket.ttlSeconds}',
      expiresAt: now.add(Duration(seconds: ticket.ttlSeconds)),
    );

    if (ticket.imgKey != null && ticket.subKey != null) {
      _ticketKeys = WbiKeys.fromKeys(
        ticket.imgKey!,
        ticket.subKey!,
        fetchedAt: now,
      );
    }
  }

  /// 取 WBI 口令。
  ///
  /// 优先用 GenWebTicket 顺带返回的（零额外请求），否则走 nav 接口。
  Future<WbiKeys> fetchWbiKeys() async {
    final cached = _ticketKeys;
    if (cached != null &&
        _clock().difference(cached.fetchedAt) < const Duration(hours: 6)) {
      return cached;
    }

    final uri = Uri.parse('${NetworkConfig.apiBase}/x/web-interface/nav');
    final response = await _httpClient
        .get(uri, headers: NetworkConfig.baseHeaders(forUri: uri))
        .timeout(timeout);
    jar.ingest(uri, _setCookieValues(response));

    final decoded = _decode(response);
    final data = decoded is Map ? decoded['data'] : null;
    final wbiImg = data is Map ? data['wbi_img'] : null;
    final imgUrl = wbiImg is Map ? wbiImg['img_url'] : null;
    final subUrl = wbiImg is Map ? wbiImg['sub_url'] : null;

    final imgKey = imgUrl is String ? WebTicket.wbiKeyFromUrl(imgUrl) : null;
    final subKey = subUrl is String ? WebTicket.wbiKeyFromUrl(subUrl) : null;
    if (imgKey == null || subKey == null) {
      // nav 在未登录时返回 code -101，但 wbi_img 依然存在；真的取不到再抛。
      throw StateError('nav 未返回 wbi_img: ${_snippet(response)}');
    }

    final keys = WbiKeys.fromKeys(imgKey, subKey, fetchedAt: _clock());
    _ticketKeys = keys;
    return keys;
  }

  /// 测试或登出时重置缓存的 WBI 口令。
  void resetWbiKeys() => _ticketKeys = null;

  void close() => _httpClient.close();

  /// 「激活」buvid：访问一次主站，回收它下发的 `_uuid` / 追踪类 Cookie。
  ///
  /// 这不是完整渲染主页——拿到响应头就丢掉 body，避免拉一大坨 HTML 阻塞启动。
  /// 失败只记日志、不阻断，搜索等接口如果之后撞风控会走 BiliClient 的 v_voucher
  /// 路径抛出清晰错误。
  Future<void> _activateBuvid() async {
    final uri = Uri.parse(NetworkConfig.webBase);
    try {
      final response = await _httpClient
          .get(uri, headers: NetworkConfig.baseHeaders(forUri: uri))
          .timeout(timeout);
      jar.ingest(uri, _setCookieValues(response));
    } catch (_) {
      // 激活失败不算致命错误——其它 Cookie 已经齐了，搜索失败时会有清晰错误。
    }
  }

  static DateTime _inAYear(DateTime now) => now.add(const Duration(days: 365));

  static List<String> _setCookieValues(http.Response response) =>
      response.headersSplitValues['set-cookie'] ?? const <String>[];

  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String _snippet(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    return text.length > 200 ? '${text.substring(0, 200)}...' : text;
  }
}
