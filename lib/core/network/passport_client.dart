import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:pointycastle/asymmetric/api.dart';

import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/network_config.dart';

/// B 站登录域（passport.bilibili.com）统一客户端。
///
/// 只是 [BiliClient] 的一层薄封装：把网关换成 passport 域，并保持"返回 `data`
/// 对象"的历史签名（登录页 / 验证码 / 扫码服务都按这个形状取值）。
///
/// 之所以不自己发请求了：Cookie 语义统一落在 [NetworkConfig.cookieJar] 上 ——
/// 扫码确认 / 密码登录 / 短信登录成功那一刻响应里的 `Set-Cookie` 由 BiliClient
/// 单点回收，调用方无需再自行捕获；重试、风控补签、异常归类也一并继承。
/// 除此之外还带两件登录域专属的事：[logout]（服务端注销）与 [encryptPassword]
/// （密码登录的 RSA_PKCS1 加密，见「密码加密」一节）。
///
/// ```dart
/// final data = await passport.get('/x/passport-login/web/key');
/// await passport.postForm('/x/passport-login/web/login/sms', body: {...});
/// await passport.logout();
/// ```
class PassportClient {
  PassportClient({
    http.Client? httpClient,
    CookieJar? cookieJar,
    Duration? timeout,
  }) : _client = BiliClient(
         httpClient: httpClient,
         cookieJar: cookieJar,
         baseUrl: baseUrl,
         timeout: timeout,
       );

  static const String baseUrl = NetworkConfig.passportBase;

  final BiliClient _client;

  /// GET 并返回响应中的 `data` 字段（已校验 `code == 0`）。
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async => _data(await _client.getJson(path, query: query));

  /// POST `application/x-www-form-urlencoded` 表单并返回响应中的 `data` 字段
  /// （已校验 `code == 0`）。
  Future<Map<String, dynamic>> postForm(
    String path, {
    required Map<String, String> body,
  }) async => _data(await _client.postForm(path, form: body));

  /// 退出登录：请求服务端注销当前 SESSDATA 并种下过期 Cookie。
  ///
  /// 表单参数名是 `biliCSRF`（不是 `csrf`），所以关掉 [BiliClient.postForm]
  /// 的自动注入、显式带上它。失败原样上抛——服务端没注销成功时调用方
  /// **不应**清本地会话，否则网络一抖就把用户登丢了（见 `profile_page`）。
  Future<void> logout() {
    return _client.postForm(
      '/login/exit/v2',
      form: {'biliCSRF': _client.jar.csrf ?? ''},
      includeCsrf: false,
    );
  }

  /// 关掉底层连接池（自己传了 http client 的话由调用方管理）。
  void close() => _client.close();

  /// `data` 必须是对象——登录页按 `data['captcha_key']` 之类取值，
  /// 形状不对时给出明确的传输层错误，而不是让调用方拿到 null 再崩。
  static Map<String, dynamic> _data(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const BiliNetworkException(200, 'unexpected payload');
  }

  // ------------------------------------------------------------ 密码加密

  /// 用 `/x/passport-login/web/key` 下发的 PEM 公钥加密密码。
  ///
  /// 服务端语义：`base64(RSA_PKCS1(盐 + 明文密码))` —— 不是历史上按
  /// `sha256(盐 + 密码)` 的旧算法（B 站服务端已不认）。盐与公钥 **20 秒**
  /// 内有效，所以这一步要贴着提交做：先让用户过极验，最后才取 key、加密、提交。
  static String encryptPassword(
    String publicKeyPem,
    String salt,
    String password,
  ) => encryptPasswordWithKey(parsePublicKey(publicKeyPem), salt, password);

  /// 解析 X.509 `BEGIN PUBLIC KEY` PEM。
  static RSAPublicKey parsePublicKey(String pem) {
    final parsed = encrypt.RSAKeyParser().parse(pem);
    if (parsed is! RSAPublicKey) {
      throw const BiliParseException('passport key 响应不是 RSA 公钥');
    }
    return parsed;
  }

  /// RSA PKCS#1 v1.5 单块加密后 base64（与官方 Python `rsa.encrypt` 对齐）。
  static String encryptPasswordWithKey(
    RSAPublicKey publicKey,
    String salt,
    String password,
  ) {
    final keySize = (publicKey.modulus?.bitLength ?? 0) ~/ 8;
    if (keySize <= 0) {
      throw ArgumentError.value(publicKey, 'publicKey', '公钥模长异常');
    }
    final plainBytes = utf8.encode('$salt$password');
    final maxBytes = keySize - 11; // PKCS#1 v1.5 至少留 11 字节填充
    if (plainBytes.length > maxBytes) {
      throw ArgumentError.value(
        plainBytes.length,
        'salt + password',
        '密码过长：RSA 单块最多 $maxBytes 字节',
      );
    }
    final cipher = encrypt.Encrypter(
      encrypt.RSA(publicKey: publicKey, encoding: encrypt.RSAEncoding.PKCS1),
    );
    return cipher.encryptBytes(plainBytes).base64;
  }
}
