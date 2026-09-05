import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bilimusic/utils/network_config.dart';

/// 二维码登录服务
/// 封装 B 站 web 端扫码登录的两个接口
///   - generate(): https://passport.bilibili.com/x/passport-login/web/qrcode/generate
///   - poll():    https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=...
class QrLoginService {
  static const String _generateUrl =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
  static const String _pollUrl =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';

  /// 申请二维码
  /// 返回 url（二维码内容）+ qrcode_key（轮询密钥，180 秒有效）
  Future<QrLoginInfo> generate() async {
    final response = await http.get(
      Uri.parse(_generateUrl),
      headers: NetworkConfig.biliHeaders,
    );
    if (response.statusCode != 200) {
      throw QrLoginException('申请二维码失败: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw QrLoginException('申请二维码失败: ${body['message']}');
    }
    final data = body['data'] as Map<String, dynamic>;
    return QrLoginInfo(
      url: data['url'] as String,
      qrcodeKey: data['qrcode_key'] as String,
    );
  }

  /// 轮询一次状态
  /// 返回 QrPollResult 包含 status 和 Set-Cookie 头（登录成功时携带）
  Future<QrPollResult> poll(String qrcodeKey) async {
    final response = await http.get(
      Uri.parse('$_pollUrl?qrcode_key=$qrcodeKey'),
      headers: NetworkConfig.biliHeaders,
    );
    if (response.statusCode != 200) {
      throw QrLoginException('轮询失败: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw QrLoginException('轮询失败: ${body['message']}');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final statusCode = (data['code'] as num?)?.toInt() ?? -1;
    final status = QrPollStatus.fromCode(statusCode);
    return QrPollResult(
      status: status,
      cookies: NetworkConfig.parseSetCookieHeaders(
        response.headers['set-cookie'] ?? '',
      ),
    );
  }
}

class QrLoginInfo {
  final String url;
  final String qrcodeKey;
  const QrLoginInfo({required this.url, required this.qrcodeKey});
}

enum QrPollStatus {
  /// 未扫码
  waiting,

  /// 已扫码未确认
  scanned,

  /// 登录成功
  success,

  /// 二维码已失效
  expired,

  /// 未知状态
  unknown;

  static QrPollStatus fromCode(int code) {
    switch (code) {
      case 86101:
        return QrPollStatus.waiting;
      case 86090:
        return QrPollStatus.scanned;
      case 0:
        return QrPollStatus.success;
      case 86038:
        return QrPollStatus.expired;
      default:
        return QrPollStatus.unknown;
    }
  }
}

class QrPollResult {
  final QrPollStatus status;
  final Map<String, String> cookies;
  const QrPollResult({required this.status, required this.cookies});
}

class QrLoginException implements Exception {
  final String message;
  QrLoginException(this.message);
  @override
  String toString() => message;
}
