import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bilimusic/api/bili_exception.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 统一的 B 站 HTTP 客户端。
///
/// 职责：
///   - 套用 [NetworkConfig.biliHeaders]（含运行时可变的 cookies）
///   - 校验 `statusCode == 200`
///   - 解析 JSON 并校验 `code == 0`
///   - 把异常统一为 [BiliApiException] / [BiliNetworkException]
///
/// 调用方不再关心 headers / cookies / 错误码格式：
/// ```dart
/// final data = await client.getJson('/x/web-interface/view', query: {'bvid': bvid});
/// ```
class BiliClient {
  BiliClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? http.Client();

  static const String baseUrl = 'https://api.bilibili.com';

  final http.Client _httpClient;
  final Duration timeout;

  /// 底层 [http.Client]，给需要直读响应体的场景（如音频 URL）复用。
  http.Client get httpClient => _httpClient;

  /// 拼接完整 URL。
  Uri _buildUri(String path, Map<String, String>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final qp = query == null || query.isEmpty
        ? <String, String>{}
        : Map<String, String>.from(query);
    return Uri.parse('$baseUrl$normalized').replace(queryParameters: qp);
  }

  Map<String, String> _buildHeaders(Map<String, String>? extra) {
    final headers = Map<String, String>.from(NetworkConfig.biliHeaders);
    headers['Content-Type'] ??= 'application/json';
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  /// GET 请求并返回响应中的 `data` 字段（已校验 `code == 0`）。
  ///
  /// 若 `data` 字段缺失但 `code == 0`，抛出 [BiliApiException]。
  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final json = await _getRaw(path, query: query, extraHeaders: extraHeaders);
    return json['data'];
  }

  /// GET 请求并返回完整 JSON map（已校验 `code == 0`）。
  ///
  /// 用于调用方要读 `numPages` / `page` / `has_more` 等顶层字段的场景。
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final json = await _getRaw(path, query: query, extraHeaders: extraHeaders);
    return json;
  }

  /// 底层 GET，把 HTTP / JSON 错误统一为 [BiliNetworkException] / [BiliApiException]。
  Future<Map<String, dynamic>> _getRaw(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _buildUri(path, query);
    final headers = _buildHeaders(extraHeaders);

    final http.Response response;
    try {
      response = await _httpClient.get(uri, headers: headers).timeout(timeout);
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

    return decoded;
  }

  void close() => _httpClient.close();
}
