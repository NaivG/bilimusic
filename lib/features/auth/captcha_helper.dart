import 'package:flutter/foundation.dart';
import 'package:gt3_flutter_plugin/gt3_flutter_plugin.dart';
import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/core/network/passport_client.dart';

class CaptchaHelper {
  static final CaptchaHelper _instance = CaptchaHelper._internal();
  final PassportClient _passport = PassportClient();
  Gt3FlutterPlugin? _captcha;
  CaptchaCallback? _callback;

  factory CaptchaHelper() {
    return _instance;
  }

  CaptchaHelper._internal() {
    _initCaptcha();
  }

  void _initCaptcha() {
    try {
      Gt3CaptchaConfig config = Gt3CaptchaConfig();
      _captcha = Gt3FlutterPlugin(config);

      _captcha?.addEventHandler(
        onShow: (Map<String, dynamic> message) async {
          _callback?.onShow?.call(message);
        },
        onClose: (Map<String, dynamic> message) async {
          _callback?.onClose?.call(message);
        },
        onResult: (Map<String, dynamic> message) async {
          String code = message["code"];
          if (code == "1") {
            var result = message["result"] as Map;
            _callback?.onResult?.call(
              result.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            );
          } else {
            _callback?.onError?.call(message);
          }
        },
        onError: (Map<String, dynamic> message) async {
          _callback?.onError?.call(message);
        },
      );
    } catch (e) {
      debugPrint("Captcha event handler exception: $e");
    }
  }

  Future<Map<String, dynamic>?> getCaptchaData() async {
    try {
      final data = await _passport.get(
        '/x/passport-login/captcha',
        query: {'source': 'main_web'},
      );
      return {
        'token': data['token'],
        'gt': data['geetest']['gt'],
        'challenge': data['geetest']['challenge'],
      };
    } on BiliException catch (e) {
      debugPrint("获取验证码数据失败: $e");
    }

    return null;
  }

  void startCaptcha(String gt, String challenge, CaptchaCallback callback) {
    _callback = callback;
    Gt3RegisterData registerData = Gt3RegisterData(
      gt: gt,
      challenge: challenge,
      success: true,
    );
    _captcha?.startCaptcha(registerData);
  }

  void closeCaptcha() {
    _captcha?.close();
  }
}

class CaptchaCallback {
  final Function(Map<String, dynamic> message)? onShow;
  final Function(Map<String, dynamic> message)? onClose;
  final Function(Map<String, String> result)? onResult;
  final Function(Map<String, dynamic> message)? onError;

  CaptchaCallback({this.onShow, this.onClose, this.onResult, this.onError});
}
