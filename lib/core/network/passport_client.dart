import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/core/network/network_config.dart';

/// B 站登录域（passport.bilibili.com）统一客户端。
///
/// 与 [BiliClient] 共用同一套校验管道（HTTP 200 → JSON → `code == 0`）与
/// 异常体系（[BiliApiException] / [BiliNetworkException]），差异：
///   - baseUrl 为 passport 域；
///   - POST 走 `application/x-www-form-urlencoded` 表单；
///   - 每个已校验响应的 Set-Cookie 经 [NetworkConfig.captureFrom] 落地 ——
///     登录 / 扫码轮询成功的会话 cookie 由此单点入库，调用方无需再自行捕获。
///
/// ```dart
/// final data = await passport.get('/x/passport-login/web/key');
/// ```
class PassportClient {
  PassportClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? http.Client();

  static const String baseUrl = 'https://passport.bilibili.com';

  final http.Client _httpClient;
  final Duration timeout;

  Uri _buildUri(String path, Map<String, String>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final qp = query == null || query.isEmpty
        ? <String, String>{}
        : Map<String, String>.from(query);
    return Uri.parse('$baseUrl$normalized').replace(queryParameters: qp);
  }

  Map<String, String> _buildHeaders({required bool form}) {
    final headers = Map<String, String>.from(NetworkConfig.biliHeaders);
    if (form) headers['Content-Type'] = 'application/x-www-form-urlencoded';
    return headers;
  }

  /// GET 请求并返回响应中的 `data` 字段（已校验 `code == 0`）。
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) {
    return _send(_buildUri(path, query), form: false);
  }

  /// POST `application/x-www-form-urlencoded` 表单并返回响应中的 `data` 字段
  /// （已校验 `code == 0`）。
  Future<Map<String, dynamic>> postForm(
    String path, {
    required Map<String, String> body,
  }) {
    return _send(_buildUri(path, null), form: true, body: body);
  }

  Future<Map<String, dynamic>> _send(
    Uri uri, {
    required bool form,
    Map<String, String>? body,
  }) async {
    final http.Response response;
    try {
      final Future<http.Response> request = form
          ? _httpClient.post(uri, headers: _buildHeaders(form: true), body: body)
          : _httpClient.get(uri, headers: _buildHeaders(form: false));
      response = await request.timeout(timeout);
    } on TimeoutException catch (e) {
      throw BiliNetworkException(null, 'timeout: $e');
    } catch (e) {
      throw BiliNetworkException(null, 'network error: $e');
    }

    if (response.statusCode != 200) {
      throw BiliNetworkException(
        response.statusCode,
        'unexpected status: ${response.body}',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw BiliNetworkException(response.statusCode, 'invalid json: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw BiliNetworkException(response.statusCode, 'unexpected payload');
    }

    final code = decoded['code'];
    if (code is! int || code != 0) {
      throw BiliApiException(
        code is int ? code : -1,
        decoded['message']?.toString() ?? 'unknown error',
      );
    }

    // 业务成功才落地 Set-Cookie（登录失败的响应不携带会话 cookie）。
    NetworkConfig.captureFrom(response.headers);

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw BiliNetworkException(response.statusCode, 'unexpected payload');
    }
    return data;
  }

  void close() => _httpClient.close();
}
