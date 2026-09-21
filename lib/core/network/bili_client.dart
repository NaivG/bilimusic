import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/network/wbi.dart';

/// 命中风控时的回调，便于上层弹验证码 / 提示降频。
typedef RiskControlHandler = void Function(BiliApiException error, Uri uri);

/// 统一的 B 站 HTTP 客户端。
///
/// 一层负责到底的事情：
///   - 按目标域名注入请求头（UA / Referer / Origin / Accept-Language）与 Cookie
///   - 回收响应里的 `Set-Cookie`（用 `headersSplitValues`，不靠正则猜逗号边界）
///   - 校验 `statusCode == 200` 与业务 `code == 0`，统一抛 [BiliException]
///   - 传输层失败按退避重试；写请求自动带 `csrf`
///   - WBI **按需签名**：`signed: true` 才签；没签名却撞上风控时自动补签重试一次
///
/// 典型用法：
/// ```dart
/// final client = BiliClient();
/// final data = await client.get('/x/web-interface/view', query: {'bvid': bvid});
/// final signed = await client.get('/x/space/wbi/acc/info', query: {'mid': 2}, signed: true);
/// final result = await client.postForm('/x/v3/fav/resource/deal', form: {'rid': 1, 'type': 2});
/// ```
class BiliClient {
  BiliClient({
    http.Client? httpClient,
    this.cookieJar,
    this.wbiSigner,
    String? baseUrl,
    Duration? timeout,
    this.maxAttempts = 2,
    this.retryBaseDelay = const Duration(milliseconds: 300),
    bool? wbiOnRiskControl,
    math.Random? random,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       baseUrl = baseUrl ?? NetworkConfig.apiBase,
       timeout = timeout ?? NetworkConfig.timeout,
       wbiOnRiskControl = wbiOnRiskControl ?? NetworkConfig.wbiOnRiskControl,
       _random = random ?? math.Random();

  /// 显式注入的 Cookie 仓库；为 null 时用 [NetworkConfig.cookieJar]。
  final CookieJar? cookieJar;

  /// 显式注入的签名器；为 null 时用 [NetworkConfig.wbiSigner]。
  final WbiSigner? wbiSigner;

  /// 默认网关。
  final String baseUrl;

  /// 单次请求超时。
  final Duration timeout;

  /// 传输层最大尝试次数（含首次）。业务错误不重试。
  final int maxAttempts;

  /// 退避基数，实际等待 = base * 2^(n-1) ± 30% 抖动。
  final Duration retryBaseDelay;

  /// 未签名请求撞上风控时，是否自动补签重试一次。
  final bool wbiOnRiskControl;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final math.Random _random;

  /// 命中风控时回调（无论当次是否已签名）。
  RiskControlHandler? onRiskControl;

  CookieJar get jar => cookieJar ?? NetworkConfig.cookieJar;

  WbiSigner get wbi => wbiSigner ?? NetworkConfig.wbiSigner;

  /// GET 并返回完整响应体（已校验 `code == 0`）。
  ///
  /// 需要读 `page` / `has_more` 等顶层字段时用它；只关心数据用 [get]。
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, Object?>? query,
    bool signed = false,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
  }) => _send(
    'GET',
    path,
    query: query,
    signed: signed,
    headers: headers,
    timeout: timeout,
    baseUrl: baseUrl,
    retry: retry,
  );

  /// GET 并返回 `data` 字段。
  Future<dynamic> get(
    String path, {
    Map<String, Object?>? query,
    bool signed = false,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
  }) async {
    final json = await getJson(
      path,
      query: query,
      signed: signed,
      headers: headers,
      timeout: timeout,
      baseUrl: baseUrl,
      retry: retry,
    );
    return json['data'];
  }

  /// POST 表单（`application/x-www-form-urlencoded`）。
  ///
  /// 写接口默认带 `csrf`（Cookie 里的 `bili_jct`），未登录时为空串——
  /// 与 Web 端行为一致，接口自己会返回 -111 之类。
  Future<Map<String, dynamic>> postForm(
    String path, {
    Map<String, Object?>? form,
    Map<String, Object?>? query,
    bool signed = false,
    bool includeCsrf = true,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
  }) {
    final body = <String, Object?>{...?form};
    if (includeCsrf) body['csrf'] = jar.csrf ?? '';
    return _send(
      'POST',
      path,
      query: query,
      form: body,
      signed: signed,
      headers: headers,
      timeout: timeout,
      baseUrl: baseUrl,
      retry: retry,
    );
  }

  /// 拉字节流（图片、字幕、弹幕分片等），不做 `code` 校验。
  ///
  /// [signed] 决定是否带 wbi 签名，与 [getJson] 的语义一致。
  ///
  /// [signedPath] 是**补签重试时要换用的路径**：B 站有一类接口是
  /// "老路径不签名 / `/wbi/` 新路径必须签名"的成对存在（例：
  /// `/x/v2/dm/web/seg.so` ↔ `/x/v2/dm/wbi/web/seg.so`）。
  /// 少了它，补签只会给老路径加上 `w_rid`，服务端照样拦——看起来"签名没用"。
  /// 不传时补签沿用 [path]（与 [getJson] 的行为一致）。
  ///
  /// [deflate] 为 true 时：请求上不带 `Accept-Encoding`（这样 dart:io 就不会
  /// 自动解压），拿回来的字节由调用方自己 inflate。为什么需要这个开关——
  /// 有些接口（`/x/v1/dm/list.so`）**只**回 deflate 压缩体，而
  /// `package:http` 在 dart:io 下对 `Content-Encoding: deflate` 会自动解压、
  /// 对裸 deflate 流却会原样返回，两种形态混在一起根本没法判断。
  ///
  /// 二进制响应里没有 JSON 的 `code` 字段可用，所以这里的**风控识别只能看
  /// 状态码**（HTTP 412）；"HTTP 200 返回一段 JSON 错误体"那种形态二进制
  /// 解码器分辨不出来，由上层用 [isErrorEnvelope] 判断并补签重试。
  Future<Uint8List> getBytes(
    String path, {
    Map<String, Object?>? query,
    bool signed = false,
    String? signedPath,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
    bool deflate = false,
  }) async {
    var useSignature = signed;
    var signatureRetried = false;

    while (true) {
      final uri = await _buildUri(
        useSignature ? (signedPath ?? path) : path,
        query,
        signed: useSignature,
        baseUrl: baseUrl,
      );
      final requestHeaders = _headers(uri, 'GET', {
        if (deflate) 'Accept-Encoding': 'identity',
        ...?headers,
      });

      final http.Response response;
      try {
        response = await _withTransportRetry(
          () => _httpClient.get(uri, headers: requestHeaders),
          timeout: timeout ?? this.timeout,
          retry: retry,
        );
      } on BiliNetworkException catch (error) {
        // HTTP 412 是 B 站用状态码表达的风控拦截，与 JSON 路径同样处理。
        if (error.isRiskControl) {
          if (!useSignature && wbiOnRiskControl && !signatureRetried) {
            signatureRetried = true;
            useSignature = true;
            wbi.invalidate();
            continue;
          }
          onRiskControl?.call(
            BiliApiException(error.statusCode ?? -1, error.message),
            uri,
          );
        }
        rethrow;
      }

      jar.ingest(uri, response.headersSplitValues['set-cookie'] ?? const []);
      return response.bodyBytes;
    }
  }

  /// 这段字节流是不是一个 JSON 错误信封（而不是真正的二进制数据）。
  ///
  /// 用途：拉 protobuf 时服务端可能在 HTTP 200 下回一段
  /// `{"code":-352,...}`，二进制解码器只会把它当垃圾数据。调用方拿这个
  /// 判一下，命中就补签重试。
  ///
  /// 判定很保守——必须能当 UTF-8 解、首字符是 `{`、且能 `jsonDecode` 成
  /// 带 `code` 的对象。真 protobuf 的首字节是字段 tag（常见 `0x0A`），
  /// 不会误判。
  static BiliApiException? isErrorEnvelope(Uint8List bytes) {
    if (bytes.isEmpty || bytes[0] != 0x7B /* '{' */ ) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    return _apiError(
      Map<String, dynamic>.from(decoded),
      http.Response('', 200),
    );
  }

  /// 当前登录态。
  ///
  /// nav 在未登录时返回 `code: -101`，这里把它当作"未登录"而不是异常。
  Future<bool> checkLogin() async {
    try {
      final data = await get('/x/web-interface/nav');
      if (data is! Map) return false;
      // nav 用的是驼峰 isLogin，这里两种写法都认。
      return data['isLogin'] == true || data['is_login'] == true;
    } on BiliApiException catch (error) {
      if (error.isNotLogin) return false;
      rethrow;
    }
  }

  /// 关闭底层连接池（自己传了 [http.Client] 的话不关，由调用方管理）。
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  // ---------------------------------------------------------------- 内部实现

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? form,
    bool signed = false,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
  }) async {
    var useSignature = signed;
    var signatureRetried = false;
    final effectiveTimeout = timeout ?? this.timeout;

    while (true) {
      final uri = await _buildUri(
        path,
        query,
        signed: useSignature,
        baseUrl: baseUrl,
      );

      final http.Response response;
      try {
        response = await _withTransportRetry(
          () => _dispatch(method, uri, _headers(uri, method, headers), form),
          timeout: effectiveTimeout,
          retry: retry,
        );
      } on BiliNetworkException catch (error) {
        // HTTP 412 是 B 站用状态码表达的风控拦截，与 -352 一起处理。
        if (error.isRiskControl) {
          if (!useSignature && wbiOnRiskControl && !signatureRetried) {
            signatureRetried = true;
            useSignature = true;
            wbi.invalidate();
            continue;
          }
          onRiskControl?.call(
            BiliApiException(error.statusCode ?? -1, error.message),
            uri,
          );
        }
        rethrow;
      }

      jar.ingest(uri, response.headersSplitValues['set-cookie'] ?? const []);
      final json = _asJsonObject(response);

      final code = json['code'];
      if (code is int && code == 0) {
        // gaia 风控的「伪成功」形态：code=0 但 data 里只有一个 v_voucher，
        // 没有 result / list / nav 等业务字段。这种形态绝不返回成功——
        // 否则 UI 会把 0 条数据当成「真的没结果」。
        if (!_isVoucherOnly(json)) return json;
      }

      final error = _voucherAwareApiError(json, response);

      // 没签名却被风控拦下：刷新口令 + 补签重试一次（不走传输层重试预算）。
      // v_voucher 形态同样走这条：未签就补签，已签就刷新口令再补签一次。
      if (error.isRiskControl && wbiOnRiskControl && !signatureRetried) {
        signatureRetried = true;
        useSignature = true;
        wbi.invalidate();
        continue;
      }

      if (error.isRiskControl) onRiskControl?.call(error, uri);
      throw error;
    }
  }

  /// 传输层重试：只针对超时 / 连接失败 / 可重试状态码；业务错误不在这里重试。
  ///
  /// 重试时会带 `Cache-Control: no-cache`：B 站部分接口（实测
  /// `/x/v2/dm/web/seg.so` 连拉两个分片时的第二个）会回 **HTTP 304**，
  /// 而这条路没有本地缓存，304 等于"空 body"——不处理就会变成
  /// "这个分片莫名其妙没弹幕"。带上 no-cache 能让中间缓存层交出完整内容。
  Future<http.Response> _withTransportRetry(
    Future<http.Response> Function() send, {
    required Duration timeout,
    required bool retry,
  }) async {
    var attempt = 1;

    while (true) {
      BiliNetworkException? failure;
      http.Response? response;

      try {
        response = await send().timeout(timeout);
      } on TimeoutException catch (error) {
        failure = BiliNetworkException(
          null,
          '请求超时（${timeout.inSeconds}s）',
          cause: error,
          isTimeout: true,
        );
      } on http.ClientException catch (error) {
        failure = BiliNetworkException(
          null,
          '网络错误：${error.message}',
          cause: error,
        );
      } catch (error) {
        failure = BiliNetworkException(null, '请求失败：$error', cause: error);
      }

      if (failure == null) {
        final result = response!;
        if (result.statusCode == 200) return result;
        failure = BiliNetworkException(
          result.statusCode,
          'HTTP ${result.statusCode}: '
          '${_snippet(utf8.decode(result.bodyBytes, allowMalformed: true))}',
        );
      }

      if (retry && attempt < maxAttempts && failure.isRetryable) {
        await _backoff(attempt);
        attempt++;
        continue;
      }
      throw failure;
    }
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, Object?>? form,
  ) {
    switch (method) {
      case 'GET':
        return _httpClient.get(uri, headers: headers);
      case 'POST':
        return _httpClient.post(
          uri,
          headers: headers,
          body: form == null ? null : _encodeForm(form),
        );
      default:
        throw ArgumentError.value(method, 'method', '暂不支持的方法');
    }
  }

  Future<Uri> _buildUri(
    String path,
    Map<String, Object?>? query, {
    required bool signed,
    String? baseUrl,
  }) async {
    final root = baseUrl ?? this.baseUrl;
    final normalized = path.startsWith('/') ? path : '/$path';
    final params = <String, Object?>{...?query};

    if (signed) {
      // 签名后的 query 必须与参与哈希的字符串逐字节一致，
      // 所以这里自己拼 query，不经过 Uri 的 queryParameters（它会把空格编成 +）。
      final signedQuery = await wbi.signQuery(params);
      return Uri.parse('$root$normalized?$signedQuery');
    }

    final uri = Uri.parse('$root$normalized');
    if (params.isEmpty) return uri;

    final encoded = <String, String>{};
    params.forEach((key, value) {
      if (value == null) return;
      encoded[key] = WbiSigner.stringify(value);
    });
    if (encoded.isEmpty) return uri;
    return uri.replace(queryParameters: encoded);
  }

  Map<String, String> _headers(
    Uri uri,
    String method, [
    Map<String, String>? extra,
  ]) {
    final headers = NetworkConfig.baseHeaders(
      forUri: uri,
      withOrigin: method != 'GET',
      accept: NetworkConfig.jsonAccept,
    );
    final cookie = jar.cookieHeaderFor(uri);
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    if (method == 'POST') {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  static String _encodeForm(Map<String, Object?> form) {
    final pairs = <String>[];
    form.forEach((key, value) {
      if (value == null) return;
      pairs.add(
        '${Uri.encodeQueryComponent(key)}='
        '${Uri.encodeQueryComponent(WbiSigner.stringify(value))}',
      );
    });
    return pairs.join('&');
  }

  static Map<String, dynamic> _asJsonObject(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (error) {
      throw BiliParseException('响应不是合法 JSON', snippet: _snippet(text));
    }
    if (decoded is! Map) {
      throw BiliParseException('响应根节点不是对象', snippet: _snippet(text));
    }
    return Map<String, dynamic>.from(decoded);
  }

  static BiliApiException _apiError(
    Map<String, dynamic> json,
    http.Response response,
  ) {
    final code = json['code'];
    final data = json['data'];
    final voucher = data is Map && data['v_voucher'] is String
        ? data['v_voucher'] as String
        : response.headers['x-bili-gaia-vvoucher'];
    return BiliApiException(
      code is int ? code : -1,
      json['message']?.toString() ?? '未知错误',
      vVoucher: voucher,
      traceId: response.headers['bili-trace-id'],
    );
  }

  /// 「code=0 但 data 里只有一个 v_voucher」= gaia 风控的伪成功形态。
  ///
  /// 真实成功响应里 data 至少有一个业务字段（result / nav / info / pages…），
  /// 而 v_voucher 单独出现时只是风控挑战凭证。把这种形态当成风控放行，会让
  /// UI 把「数据为空」当成「真的没结果」。
  static bool _isVoucherOnly(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is! int || code != 0) return false;
    final data = json['data'];
    if (data is! Map) return false;
    final voucher = data['v_voucher'];
    if (voucher is! String || voucher.isEmpty) return false;
    return data.length <= 1;
  }

  /// 把 v_voucher 形态换成 code=-352 的清晰错误，方便上层走风控链路（补签重试、
  /// onRiskControl 回调、抛给 UI 显示「搜索失败」而不是「没有结果」）。
  static BiliApiException _voucherAwareApiError(
    Map<String, dynamic> json,
    http.Response response,
  ) {
    if (_isVoucherOnly(json)) {
      final voucher = (json['data'] as Map)['v_voucher'] as String;
      return BiliApiException(
        -352,
        '风控校验失败（v_voucher）',
        vVoucher: voucher,
        traceId: response.headers['bili-trace-id'],
      );
    }
    return _apiError(json, response);
  }

  static String _snippet(String text) =>
      text.length > 200 ? '${text.substring(0, 200)}...' : text;

  Future<void> _backoff(int attempt) {
    final base = retryBaseDelay.inMilliseconds * (1 << (attempt - 1));
    final jitter = (base * 0.3 * (_random.nextDouble() * 2 - 1)).round();
    final delay = (base + jitter).clamp(0, 30000);
    return Future<void>.delayed(Duration(milliseconds: delay));
  }
}
