import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/network/passport_store.dart';
import 'package:bilimusic/features/auth/logout_session.dart';
import 'package:bilimusic/features/auth/user_manager.dart';

const _sessionCookies = [
  'SESSDATA',
  'bili_jct',
  'DedeUserID',
  'DedeUserID__ckMd5',
  'sid',
  'buvid_fp',
  'x-bili-gaia-vtoken',
];

const _deviceCookies = [
  'buvid3',
  'buvid4',
  'b_nut',
  'bili_ticket',
  '_uuid',
  'b_lsid',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CookieJar jar;
  late UserManager userManager;
  late Map<String, String> storage;
  late PassportStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    jar = CookieJar();
    for (final name in _sessionCookies) {
      jar.set(name, 'session');
    }
    for (final name in _deviceCookies) {
      jar.set(name, 'device');
    }
    NetworkConfig.configure(cookieJar: jar);
    userManager = UserManager();
    storage = {};
    store = PassportStore(
      loader: () async => storage['key'],
      saver: (json) async => storage['key'] = json,
    );
  });

  test('强制退出只清登录态，设备标识留在本地', () async {
    await store.setRefreshToken('rt-1');
    expect(userManager.checkCookieLogin(), isTrue);

    await clearLocalLoginState(passportStore: store, userManager: userManager);

    expect(jar.isLoggedIn, isFalse);
    expect(jar.csrf, isNull);
    for (final name in _sessionCookies) {
      expect(jar.value(name), isNull, reason: '$name 属于登录态，强制退出要摘掉');
    }
    for (final name in _deviceCookies) {
      expect(jar.value(name), 'device', reason: '$name 属于设备标识，强制退出要保留');
    }
    expect(await store.readRefreshToken(), isNull);
    expect(userManager.isLoggedIn, isFalse);
  });

  test('refresh_token 落盘失败不挡住本地登出', () async {
    await store.setRefreshToken('rt-2');
    final failing = PassportStore(
      loader: () async => null,
      saver: (json) async => throw StateError('磁盘写失败'),
    );

    await expectLater(
      clearLocalLoginState(passportStore: failing, userManager: userManager),
      completes,
    );

    expect(jar.isLoggedIn, isFalse);
    expect(storage['key'], contains('rt-2'), reason: '失败的写入不该影响已落盘的旧凭据');
  });

  test('可以显式指定 jar，不依赖全局 NetworkConfig', () async {
    final other = CookieJar()
      ..set('SESSDATA', 's')
      ..set('buvid3', 'dev');

    await clearLocalLoginState(
      passportStore: store,
      userManager: userManager,
      cookieJar: other,
    );

    expect(other.isLoggedIn, isFalse);
    expect(other.value('buvid3'), 'dev');
    expect(jar.isLoggedIn, isTrue, reason: '显式传入时不该动全局 jar');
  });
}
