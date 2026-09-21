import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';

import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/passport_client.dart';
import 'package:bilimusic/core/network/passport_store.dart';
import 'package:bilimusic/features/auth/qr_login_service.dart';

/// 示例公钥。
const _docsPem =
    '-----BEGIN PUBLIC KEY-----\n'
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDjb4V7EidX/ym28t2ybo0U6t0n\n'
    '6p4ej8VjqKHg100va6jkNbNTrLQqMCQCAYtXMXXp2Fwkk6WR+12N9zknLjf+C9sx\n'
    '/+l48mjUU8RqahiFD1XT/u2e0m2EN029OhCgkHx3Fc/KlFSIbak93EH/XlYis0w+\n'
    'Xl69GV6klzgxW6d2xQIDAQAB\n'
    '-----END PUBLIC KEY-----\n';

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, String> _formOf(http.Request request) =>
    Uri.splitQueryString(request.body);

void main() {
  group('PassportClient 密码加密', () {
    test('parsePublicKey 解析官方文档示例公钥（RSA 1024）', () {
      final key = PassportClient.parsePublicKey(_docsPem);
      expect(key.modulus!.bitLength, 1024);
    });

    test('encryptPassword 产出单块 base64 密文', () {
      final b64 = PassportClient.encryptPassword(
        _docsPem,
        '9333681c87fd8d6e',
        'example_password',
      );
      expect(base64Decode(b64), hasLength(128));
    });

    test('盐在密码之前：密文可被配对私钥解回原文', () {
      final (publicKey, privateKey) = _generatedPair;
      final b64 = PassportClient.encryptPasswordWithKey(
        publicKey,
        '0123456789abcdef',
        's3cret-密码',
      );
      final plain = utf8.decode(_decryptWith(privateKey, b64));
      expect(plain, '0123456789abcdefs3cret-密码');
    });

    test('超长密码明确报错而不是产出双块密文', () {
      final (publicKey, _) = _generatedPair;
      expect(
        () => PassportClient.encryptPasswordWithKey(
          publicKey,
          '0123456789abcdef',
          'x' * 200,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PassportClient.logout', () {
    test('打到 /login/exit/v2，用 biliCSRF 而不是 csrf', () async {
      final jar = CookieJar()..set('bili_jct', 'csrf-token');
      http.Request? lastRequest;
      final passport = PassportClient(
        httpClient: MockClient((request) async {
          lastRequest = request;
          return _json({
            'code': 0,
            'status': true,
            'data': {
              'redirectUrl': 'https://passport.biligame.com/crossDomain',
            },
          });
        }),
        cookieJar: jar,
      );

      await passport.logout();

      expect(lastRequest, isNotNull);
      expect(lastRequest!.method, 'POST');
      expect(lastRequest!.url.host, 'passport.bilibili.com');
      expect(lastRequest!.url.path, '/login/exit/v2');
      final form = _formOf(lastRequest!);
      expect(form['biliCSRF'], 'csrf-token');
      expect(form.containsKey('csrf'), isFalse);
    });
  });

  group('QrLoginService', () {
    test('poll 成功时带回 refresh_token，其余状态为空', () async {
      var dataCode = 0;
      final service = QrLoginService(
        client: PassportClient(
          httpClient: MockClient((request) async {
            expect(request.url.host, 'passport.bilibili.com');
            expect(request.url.path, '/x/passport-login/web/qrcode/poll');
            return _json({
              'code': 0,
              'data': {
                'code': dataCode,
                'message': 'stub',
                'url': '',
                'refresh_token': dataCode == 0 ? 'rt-1' : '',
                'timestamp': 1662363009601,
              },
            });
          }),
          cookieJar: CookieJar(),
        ),
      );

      final confirmed = await service.poll('k');
      expect(confirmed.status, QrPollStatus.success);
      expect(confirmed.refreshToken, 'rt-1');

      dataCode = 86101;
      final waiting = await service.poll('k');
      expect(waiting.status, QrPollStatus.waiting);
      expect(waiting.refreshToken, '');
    });
  });

  group('PassportStore', () {
    test('写入、重开读回、清空', () async {
      final storage = <String, String>{};
      PassportStore storeWith() => PassportStore(
        loader: () async => storage['key'],
        saver: (json) async => storage['key'] = json,
      );

      final store = storeWith();
      await store.setRefreshToken('rt-1');
      expect(store.refreshToken, 'rt-1');

      final restored = storeWith();
      expect(await restored.readRefreshToken(), 'rt-1');

      await restored.clear();
      expect(await restored.readRefreshToken(), isNull);

      final reopened = storeWith();
      expect(await reopened.readRefreshToken(), isNull);
    });

    test('无持久化宿主时退化为内存', () async {
      final store = PassportStore();
      expect(await store.readRefreshToken(), isNull);
      await store.setRefreshToken('rt-2');
      expect(store.refreshToken, 'rt-2');
    });
  });
}

// ---------------------------------------------------------------------------
// RSA 测试工具：现场生成一对 1024 位密钥（只生成一次，多个用例复用）
// ---------------------------------------------------------------------------

final (RSAPublicKey, RSAPrivateKey) _generatedPair = _generatePair();

(RSAPublicKey, RSAPrivateKey) _generatePair() {
  final secureRandom = FortunaRandom();
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  secureRandom.seed(KeyParameter(seed));
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
        secureRandom,
      ),
    );
  final pair = generator.generateKeyPair();
  return (pair.publicKey as RSAPublicKey, pair.privateKey as RSAPrivateKey);
}

Uint8List _decryptWith(RSAPrivateKey privateKey, String base64Ciphertext) {
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  return cipher.process(base64Decode(base64Ciphertext));
}
