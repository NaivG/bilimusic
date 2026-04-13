import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gt3_flutter_plugin/gt3_flutter_plugin.dart';
import 'package:bilimusic/utils/network_config.dart';

class CaptchaHelper {
  static final CaptchaHelper _instance = CaptchaHelper._internal();
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
      print("Captcha event handler exception: $e");
    }
  }

  Future<Map<String, dynamic>?> getCaptchaData() async {
    const String captchaUrl =
        'https://passport.bilibili.com/x/passport-login/captcha?source=main_web';

    try {
      final response = await http.get(
        Uri.parse(captchaUrl),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          return {
            'token': data['data']['token'],
            'gt': data['data']['geetest']['gt'],
            'challenge': data['data']['geetest']['challenge'],
          };
        }
      }
    } catch (e) {
      print("获取验证码数据失败: $e");
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
