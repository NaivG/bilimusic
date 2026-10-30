import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bilimusic/core/network/bili_bootstrap.dart';
import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/wbi.dart';

/// A/B 两组长度 32 的 WBI 模拟口令。
const _imgA = '5e1c2f0a9b4d7e3f1a2b3c4d5e6f7a8b'; // fake keys
const _subA = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
const _imgB = 'aa11bb22cc33dd44ee55ff6600778899';
const _subB = '99887766554433221100ffeeddccbbaa';

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _wbiUrl(String key) => 'https://i0.hdslb.com/bfs/wbi/$key.png';

String _wRid(Uri uri) => uri.queryParameters['w_rid']!;

/// 按签名算法复核 `w_rid`：去掉尾部的 `w_rid` 后重算 md5。
String _expectedWRid(Uri uri, String mixinKey) {
  final query = uri.query
      .split('&')
      .where((pair) => !pair.startsWith('w_rid='))
      .join('&');
  return WbiSigner.sign(query, mixinKey);
}

/// 自举阶段的假网络：finger/spi → GenWebTicket（口令 A）→ 主站激活；
/// 强制刷新口令时走 nav（口令 B）。
MockClient _bootstrapClient({
  required void Function() onNav,
  required int createdAt,
  bool failNav = false,
}) {
  return MockClient((request) async {
    final url = request.url;
    switch (url.path) {
      case '/x/frontend/finger/spi':
        return _json({
          'code': 0,
          'data': {'b_3': 'buvid3-test', 'b_4': 'buvid4-test'},
        });
      case '/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket':
        return _json({
          'code': 0,
          'data': {
            'ticket': 'ticket-test',
            'created_at': createdAt,
            'ttl': 259200,
            'nav': {'img': _wbiUrl(_imgA), 'sub': _wbiUrl(_subA)},
          },
        });
      case '/x/web-interface/nav':
        onNav();
        if (failNav) return http.Response('blocked', 500);
        return _json({
          'code': 0,
          'data': {
            'wbi_img': {'img_url': _wbiUrl(_imgB), 'sub_url': _wbiUrl(_subB)},
          },
        });
      default:
        if (url.host == 'www.bilibili.com') {
          return http.Response('<html></html>', 200);
        }
        return http.Response('unexpected ${request.method} $url', 404);
    }
  });
}

/// 起一套「已自举完」的环境：bootstrap 里已有 GenWebTicket 口令 A。
///
/// 返回的第三个值可读 nav 请求次数 —— 强制刷新口令才会打 nav。
Future<(BiliBootstrap, WbiSigner, int Function())> _bootstrapped({
  bool failNav = false,
}) async {
  var navCalls = 0;
  final bootstrap = BiliBootstrap(
    jar: CookieJar(),
    httpClient: _bootstrapClient(
      onNav: () => navCalls++,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      failNav: failNav,
    ),
  );
  addTearDown(bootstrap.close);

  await bootstrap.ensureDeviceCookies();
  expect(bootstrap.lastError, isNull);
  expect(bootstrap.hasTicket, isTrue);
  expect(navCalls, 0, reason: '自举阶段的口令来自 GenWebTicket，不该打 nav');

  return (
    bootstrap,
    WbiSigner(fetchKeys: bootstrap.fetchWbiKeys),
    () => navCalls,
  );
}

void main() {
  group('WBI 刷新口令 + 补签重试', () {
    test('-352 之后用 GenWebTicket 之外的实时口令重签', () async {
      final (bootstrap, signer, navCalls) = await _bootstrapped();
      final uris = <Uri>[];
      var calls = 0;
      final client = BiliClient(
        httpClient: MockClient((request) async {
          uris.add(request.url);
          calls++;
          if (calls == 1) {
            return _json({'code': -352, 'message': '风控校验失败'});
          }
          return _json({
            'code': 0,
            'data': {'ok': true},
          });
        }),
        cookieJar: bootstrap.jar,
        wbiSigner: signer,
        wbiOnRiskControl: true,
      );
      addTearDown(client.close);

      final data = await client.get(
        '/x/test',
        query: {'bvid': 'BV1'},
        signed: true,
      );

      expect(data, {'ok': true});
      expect(uris, hasLength(2));
      // 第一次用自举时缓存的 A，刷新后必须换成 nav 返回的 B。
      expect(
        _wRid(uris[0]),
        _expectedWRid(uris[0], WbiSigner.mixinKeyOf(_imgA, _subA)),
      );
      expect(
        _wRid(uris[1]),
        _expectedWRid(uris[1], WbiSigner.mixinKeyOf(_imgB, _subB)),
      );
      expect(navCalls(), 1, reason: '补签重试必须绕过 bootstrap 的 6 小时缓存');
    });

    test('HTTP 412 的补签重试同样换新口令，并切到 /wbi/ 路径', () async {
      final (bootstrap, signer, navCalls) = await _bootstrapped();
      final uris = <Uri>[];
      var calls = 0;
      final client = BiliClient(
        httpClient: MockClient((request) async {
          uris.add(request.url);
          calls++;
          if (calls == 1) return http.Response('blocked', 412);
          return http.Response.bytes(const [1, 2, 3], 200);
        }),
        cookieJar: bootstrap.jar,
        wbiSigner: signer,
        wbiOnRiskControl: true,
      );
      addTearDown(client.close);

      final bytes = await client.getBytes(
        '/x/v2/dm/web/seg.so',
        query: {'oid': 1},
        signedPath: '/x/v2/dm/wbi/web/seg.so',
      );

      expect(bytes, [1, 2, 3]);
      expect(uris, hasLength(2));
      expect(uris[0].path, '/x/v2/dm/web/seg.so');
      expect(uris[1].path, '/x/v2/dm/wbi/web/seg.so');
      expect(
        _wRid(uris[1]),
        _expectedWRid(uris[1], WbiSigner.mixinKeyOf(_imgB, _subB)),
      );
      expect(navCalls(), 1, reason: '补签重试必须绕过 bootstrap 的 6 小时缓存');
    });

    test('刷新口令失败时抛 BiliException，不把裸传输异常漏给上层', () async {
      final (bootstrap, signer, navCalls) = await _bootstrapped(failNav: true);
      final client = BiliClient(
        httpClient: MockClient(
          (request) async => _json({'code': -352, 'message': '风控校验失败'}),
        ),
        cookieJar: bootstrap.jar,
        wbiSigner: signer,
        wbiOnRiskControl: true,
      );
      addTearDown(client.close);

      await expectLater(
        client.get('/x/test', signed: true),
        throwsA(
          isA<BiliNetworkException>().having(
            (error) => error.message,
            'message',
            contains('WBI 口令获取失败'),
          ),
        ),
      );
      expect(navCalls(), 1);
    });
  });
}
