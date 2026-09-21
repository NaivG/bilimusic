import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/bili_cookie.dart';
import 'package:bilimusic/core/network/cookie_jar.dart';

/// CookieJar：旧格式迁移 / 域路径语义 / Set-Cookie 回收。
///
/// 全部是纯 Dart 逻辑（无插件、无网络），构造时注入固定时钟与内存 loader/saver。
void main() {
  final fixedNow = DateTime.utc(2026, 1, 1);

  CookieJar jarWith({String? stored, void Function(String json)? onSave}) {
    return CookieJar(
      loader: () async => stored,
      saver: onSave == null ? null : (json) async => onSave(json),
      clock: () => fixedNow,
    );
  }

  group('旧格式一次性迁移', () {
    test('扁平 JSON 展开成完整 Cookie，并按新格式回写', () async {
      String? saved;
      final jar = jarWith(
        stored: jsonEncode({
          'SESSDATA': 'abc',
          'buvid3': 'b3',
          'bili_jct': 'jct',
        }),
        onSave: (json) => saved = json,
      );

      await jar.load();
      await jar.save(); // load 里的回写是串行队列上的，这里等一次队列

      expect(jar.isLoggedIn, isTrue, reason: '老用户不该掉登录');
      expect(jar.value('buvid3'), 'b3');
      expect(jar.csrf, 'jct');

      final written = jsonDecode(saved!) as Map<String, dynamic>;
      expect(written['version'], 1);
      final cookies = (written['cookies'] as List).cast<Map>();
      expect(cookies, hasLength(3));
      final sessdata = cookies.firstWhere((c) => c['name'] == 'SESSDATA');
      expect(sessdata['domain'], CookieJar.legacyDomain);
      expect(sessdata['path'], '/');
      expect(sessdata['value'], 'abc');
      expect(sessdata['expiresAt'], isNotNull);
    });

    test('裸 Cookie 串也能迁移（更早的字符串形态）', () async {
      final jar = jarWith(stored: 'SESSDATA=abc; buvid3=b3');
      await jar.load();
      expect(jar.value('SESSDATA'), 'abc');
      expect(jar.value('buvid3'), 'b3');
    });

    test('迁移出的 Cookie 只发给 bilibili.com 及其子域', () async {
      final jar = jarWith(stored: jsonEncode({'SESSDATA': 'abc'}));
      await jar.load();
      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x')),
        'SESSDATA=abc',
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://i0.hdslb.com/a.jpg')),
        isNull,
        reason: '图片域不在 bilibili.com 下，不该带登录 Cookie',
      );
    });

    test('新格式读回来与写出去一致（往返）', () async {
      String? saved;
      final first = jarWith(
        stored: jsonEncode({'SESSDATA': 'abc', 'buvid4': 'b4'}),
        onSave: (json) => saved = json,
      );
      await first.load();
      await first.save();

      final second = jarWith(stored: saved);
      await second.load();
      expect(second.value('SESSDATA'), 'abc');
      expect(second.value('buvid4'), 'b4');
      expect(second.all, hasLength(2));
    });

    test('新格式里已过期的条目不会载入', () async {
      final payload = jsonEncode({
        'version': 1,
        'cookies': [
          {
            'name': 'SESSDATA',
            'value': 'stale',
            'domain': 'bilibili.com',
            'path': '/',
            'expiresAt': fixedNow
                .subtract(const Duration(days: 1))
                .toIso8601String(),
          },
          {
            'name': 'buvid3',
            'value': 'b3',
            'domain': 'bilibili.com',
            'path': '/',
          },
        ],
      });

      final jar = jarWith(stored: payload);
      await jar.load();

      expect(jar.value('SESSDATA'), isNull);
      expect(jar.value('buvid3'), 'b3');
    });

    test('没有 loader 时退化成纯内存（CLI / 测试可用）', () async {
      final jar = CookieJar(clock: () => fixedNow);
      await jar.load();
      expect(jar.isEmpty, isTrue);
      jar.set('SESSDATA', 'abc');
      await jar.save(); // saver 为 null，不该抛
      expect(jar.isLoggedIn, isTrue);
    });
  });

  group('域 / 路径 / 安全性', () {
    test('按域名回传，不发给无关域', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('SESSDATA', 'abc');

      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x')),
        'SESSDATA=abc',
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://www.bilibili.com/')),
        'SESSDATA=abc',
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://i0.hdslb.com/a.jpg')),
        isNull,
      );
    });

    test('hostOnly 只对下发它的主机生效', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.ingest(Uri.parse('https://www.bilibili.com/'), ['foo=1; Path=/']);

      expect(
        jar.cookieHeaderFor(Uri.parse('https://www.bilibili.com/x')),
        'foo=1',
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x')),
        isNull,
      );
    });

    test('路径前缀匹配的边界必须是 /', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('a', '1', path: '/x');

      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x/y')),
        'a=1',
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/xyz')),
        isNull,
        reason: '/xyz 不该命中 path=/x',
      );
    });

    test('路径更具体的排在前面（RFC 6265 §5.4）', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('a', '1', path: '/');
      jar.set('b', '2', path: '/x/');

      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x/y')),
        'b=2; a=1',
      );
    });

    test('secure Cookie 不在 http 上回传', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('SESSDATA', 'abc'); // 默认 secure: true

      expect(
        jar.cookieHeaderFor(Uri.parse('http://api.bilibili.com/x')),
        isNull,
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x')),
        'SESSDATA=abc',
      );
    });

    test('过期条目既不出现在清单里，也不回传', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set(
        'a',
        '1',
        expiresAt: fixedNow.subtract(const Duration(seconds: 1)),
      );

      expect(jar.all, isEmpty);
      expect(jar.isEmpty, isTrue);
      expect(
        jar.cookieHeaderFor(Uri.parse('https://api.bilibili.com/x')),
        isNull,
      );
    });
  });

  group('Set-Cookie 回收', () {
    test('解析属性并入库', () {
      final jar = CookieJar(clock: () => fixedNow);
      final changed = jar.ingest(Uri.parse('https://api.bilibili.com/x'), [
        'SESSDATA=abc; Path=/; Domain=.bilibili.com; '
            'Expires=Sat, 26 Jul 2026 06:38:43 GMT; Secure; HttpOnly',
      ]);

      expect(changed, ['SESSDATA']);
      final cookie = jar.all.single;
      expect(cookie.domain, 'bilibili.com');
      expect(cookie.path, '/');
      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.expiresAt, DateTime.utc(2026, 7, 26, 6, 38, 43));
    });

    test('Max-Age=0 表示删除', () {
      final jar = CookieJar(clock: () => fixedNow);
      final uri = Uri.parse('https://api.bilibili.com/x');
      jar.ingest(uri, ['SESSDATA=abc; Path=/; Domain=.bilibili.com']);
      expect(jar.value('SESSDATA'), 'abc');

      final changed = jar.ingest(uri, [
        'SESSDATA=; Path=/; Domain=.bilibili.com; Max-Age=0',
      ]);
      expect(changed, contains('SESSDATA'));
      expect(jar.value('SESSDATA'), isNull);
    });

    test('值没变的重复下发不算变更', () {
      final jar = CookieJar(clock: () => fixedNow);
      final uri = Uri.parse('https://api.bilibili.com/x');
      jar.ingest(uri, ['foo=1; Path=/']);
      expect(jar.ingest(uri, ['foo=1; Path=/']), isEmpty);
      expect(jar.ingest(uri, ['foo=2; Path=/']), ['foo']);
    });

    test('越权域名直接丢弃（RFC 6265 §5.3）', () {
      final jar = CookieJar(clock: () => fixedNow);
      final changed = jar.ingest(Uri.parse('https://api.bilibili.com/x'), [
        'evil=1; Domain=example.com',
      ]);

      expect(changed, isEmpty);
      expect(jar.isEmpty, isTrue);
    });

    test('被合并成一条的多个 Set-Cookie 会被拆开，Expires 里的逗号不误切', () {
      final parts = SetCookieParser.splitMerged(
        'a=1; Expires=Sat, 26 Jul 2025 06:38:43 GMT, b=2; Path=/',
      );

      expect(parts, hasLength(2));
      expect(parts.first, contains('Expires=Sat, 26 Jul 2025 06:38:43 GMT'));
      expect(parts.last, 'b=2; Path=/');
    });

    test('没有逗号时原样返回', () {
      expect(SetCookieParser.splitMerged('a=1; Path=/'), ['a=1; Path=/']);
    });

    test('三种 HTTP 日期格式都能解', () {
      final rfc1123 = SetCookieParser.parseHttpDate(
        'Sat, 26 Jul 2025 06:38:43 GMT',
      );
      final rfc850 = SetCookieParser.parseHttpDate(
        'Sunday, 06-Nov-94 08:49:37 GMT',
      );
      final asctime = SetCookieParser.parseHttpDate('Sun Nov  6 08:49:37 1994');

      expect(rfc1123, DateTime.utc(2025, 7, 26, 6, 38, 43));
      expect(rfc850, DateTime.utc(1994, 11, 6, 8, 49, 37));
      expect(asctime, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });
  });

  group('clearSession', () {
    test('只摘会话 Cookie，设备标识留在盘上', () {
      final jar = CookieJar(clock: () => fixedNow);
      const sessionKeys = [
        'SESSDATA',
        'bili_jct',
        'DedeUserID',
        'DedeUserID__ckMd5',
        'sid',
        'buvid_fp',
      ];
      const deviceKeys = [
        'buvid3',
        'buvid4',
        'b_nut',
        'bili_ticket',
        '_uuid',
        'b_lsid',
      ];
      for (final name in [...sessionKeys, ...deviceKeys]) {
        jar.set(name, 'v');
      }

      jar.clearSession();

      expect(jar.isLoggedIn, isFalse);
      expect(jar.csrf, isNull);
      for (final name in sessionKeys) {
        expect(jar.value(name), isNull, reason: '$name 属于登录态，登出要摘掉');
      }
      for (final name in deviceKeys) {
        expect(jar.value(name), 'v', reason: '$name 属于设备标识，登出后保留（否则下次启动要从零自举）');
      }
    });

    test('clear 则一份不留', () {
      final jar = CookieJar(clock: () => fixedNow);
      jar.set('SESSDATA', 'v');
      jar.set('buvid3', 'v');

      jar.clear();

      expect(jar.isEmpty, isTrue);
    });
  });
}
