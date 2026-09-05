import 'package:bilimusic/core/network/passport_client.dart';

/// 二维码登录服务
/// 封装 B 站 web 端扫码登录的两个接口
///   - generate(): https://passport.bilibili.com/x/passport-login/web/qrcode/generate
///   - poll():    https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=...
///
/// Set-Cookie 由 [PassportClient] 统一落地（登录成功即完成会话写入），
/// 调用方无需再自行捕获；HTTP / 业务错误统一为 BiliException。
class QrLoginService {
  QrLoginService({PassportClient? client})
    : _passport = client ?? PassportClient();

  final PassportClient _passport;

  /// 申请二维码
  /// 返回 url（二维码内容）+ qrcode_key（轮询密钥，180 秒有效）
  Future<QrLoginInfo> generate() async {
    final data = await _passport.get('/x/passport-login/web/qrcode/generate');
    return QrLoginInfo(
      url: data['url'] as String,
      qrcodeKey: data['qrcode_key'] as String,
    );
  }

  /// 轮询一次状态
  Future<QrPollResult> poll(String qrcodeKey) async {
    final data = await _passport.get(
      '/x/passport-login/web/qrcode/poll',
      query: {'qrcode_key': qrcodeKey},
    );
    final statusCode = (data['code'] as num?)?.toInt() ?? -1;
    return QrPollResult(status: QrPollStatus.fromCode(statusCode));
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
  const QrPollResult({required this.status});
}
