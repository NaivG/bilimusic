import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/network_config.dart';

/// 请求头装配：Referer 按目标域名取、写请求才带 Origin、Cookie 按域回传。
void main() {
  final fixedNow = DateTime.utc(2026, 1, 1);

  tearDown(() {
    // 全局单例：每个用例结束后换回一个干净的内存 jar，避免互相串味。
    NetworkConfig.configure(cookieJar: CookieJar());
  });

  group('baseHeaders', () {
    test('Referer 按目标域名取，且不会拼出双斜杠', () {
      String referer(String url) =>
          NetworkConfig.baseHeaders(forUri: Uri.parse(url))['Referer']!;

      expect(
        referer('https://api.bilibili.com/x/web-interface/nav'),
        'https://www.bilibili.com/',
      );
      expect(
        referer('https://passport.bilibili.com/x/passport-login/web/key'),
        'https://www.bilibili.com/',
      );
      expect(
        referer('https://search.bilibili.com/all?keyword=x'),
        'https://search.bilibili.com/',
      );
      expect(
        referer('https://www.bilibili.com/video/BV1'),
        'https://www.bilibili.com/',
      );
      // 不传目标时退化成主站
      expect(
        NetworkConfig.baseHeaders()['Referer'],
        'https://www.bilibili.com/',
      );
      for (final url in [
        'https://api.bilibili.com/x',
        'https://passport.bilibili.com/x',
        'https://search.bilibili.com/x',
      ]) {
        // 去掉协议头后不该再出现 `//`（`https://www.bilibili.com//` 是拼错的来源）
        expect(
          referer(url).replaceFirst('https://', ''),
          isNot(contains('//')),
          reason: '双斜杠会被服务端当异常来源',
        );
      }
    });

    test('UA / Accept-Language 固定，Accept 可覆盖', () {
      final headers = NetworkConfig.baseHeaders(
        forUri: Uri.parse('https://api.bilibili.com/x'),
        accept: NetworkConfig.jsonAccept,
      );

      expect(headers['User-Agent'], NetworkConfig.userAgent);
      expect(headers['User-Agent'], contains('Firefox'));
      expect(headers['Accept'], NetworkConfig.jsonAccept);
      expect(headers['Accept-Language'], isNotEmpty);
    });

    test('只有写请求带 Origin（同站 GET 带 Origin 更像脚本）', () {
      final uri = Uri.parse('https://api.bilibili.com/x');

      expect(
        NetworkConfig.baseHeaders(forUri: uri).containsKey('Origin'),
        isFalse,
      );
      expect(
        NetworkConfig.baseHeaders(forUri: uri, withOrigin: true)['Origin'],
        NetworkConfig.webBase,
      );
    });
  });

  group('headersFor / biliHeaders', () {
    test('装配该域名该带的 Cookie', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('SESSDATA', 'abc');
      NetworkConfig.configure(cookieJar: jar);

      final api = NetworkConfig.headersFor(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
      );
      expect(api['Cookie'], 'SESSDATA=abc');
      expect(api['Referer'], 'https://www.bilibili.com/');
    });

    test('无关域名不带 Cookie', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('SESSDATA', 'abc');
      NetworkConfig.configure(cookieJar: jar);

      final image = NetworkConfig.headersFor(
        Uri.parse('https://i0.hdslb.com/bfs/archive/a.jpg'),
      );
      expect(image.containsKey('Cookie'), isFalse);
      expect(image['Referer'], 'https://www.bilibili.com/');
    });

    test('biliHeaders 是给封面 / 头像用的一套固定头（按主站域取 Cookie）', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('SESSDATA', 'abc');
      NetworkConfig.configure(cookieJar: jar);

      final headers = NetworkConfig.biliHeaders;
      expect(headers['Cookie'], 'SESSDATA=abc');
      expect(headers['Referer'], 'https://www.bilibili.com/');
      expect(headers['User-Agent'], NetworkConfig.userAgent);
    });

    test('没有 Cookie 时不写 Cookie 头（而不是发一个空串）', () {
      NetworkConfig.configure(cookieJar: CookieJar(clock: () => fixedNow));
      expect(
        NetworkConfig.headersFor(Uri.parse('https://api.bilibili.com/x'))
            .containsKey('Cookie'),
        isFalse,
      );
    });
  });

  group('configure', () {
    test('换 jar 会连带重建 bootstrap / wbiSigner（它们持有旧 jar 的引用）', () {
      NetworkConfig.configure(cookieJar: CookieJar(clock: () => fixedNow));
      final bootstrap = NetworkConfig.bootstrap;
      final signer = NetworkConfig.wbiSigner;

      NetworkConfig.configure(cookieJar: CookieJar(clock: () => fixedNow));

      expect(identical(bootstrap, NetworkConfig.bootstrap), isFalse);
      expect(identical(signer, NetworkConfig.wbiSigner), isFalse);
    });

    test('同一个 jar 反复取 bootstrap / wbiSigner 是同一个实例', () {
      NetworkConfig.configure(cookieJar: CookieJar(clock: () => fixedNow));
      expect(
        identical(NetworkConfig.bootstrap, NetworkConfig.bootstrap),
        isTrue,
      );
      expect(
        identical(NetworkConfig.wbiSigner, NetworkConfig.wbiSigner),
        isTrue,
      );
    });

    test('超时与补签开关可配置', () {
      NetworkConfig.configure(
        timeout: const Duration(seconds: 3),
        wbiOnRiskControl: false,
      );
      expect(NetworkConfig.timeout, const Duration(seconds: 3));
      expect(NetworkConfig.wbiOnRiskControl, isFalse);

      NetworkConfig.configure(
        timeout: const Duration(seconds: 15),
        wbiOnRiskControl: true,
      );
      expect(NetworkConfig.timeout, const Duration(seconds: 15));
      expect(NetworkConfig.wbiOnRiskControl, isTrue);
    });

    test('常量网关地址没被改歪', () {
      expect(NetworkConfig.apiBase, 'https://api.bilibili.com');
      expect(NetworkConfig.webBase, 'https://www.bilibili.com');
      expect(NetworkConfig.searchBase, 'https://search.bilibili.com');
      expect(NetworkConfig.passportBase, 'https://passport.bilibili.com');
    });
  });
}
