import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/wbi.dart';

/// WBI 签名测试。
void main() {
  const imgKey = '7cd084941338484aae1ad9425b84077c';
  const subKey = '4932caff0ff746eab6f01bf08b70ac45';
  const mixinKey = 'ea1db124af3c7062474693fa704f4ff8';

  group('签名算法', () {
    test('mixinKeyOf 按重排表取前 32 位', () {
      expect(WbiSigner.mixinKeyOf(imgKey, subKey), mixinKey);
    });

    test('口令不足 64 位直接报错（不静默签出一个错的 w_rid）', () {
      expect(
        () => WbiSigner.mixinKeyOf('short', 'alsoshort'),
        throwsArgumentError,
      );
    });

    test('signWithKeys 复现官方示例的 query 与 w_rid', () {
      final signed = WbiSigner.signWithKeys(
        {'foo': 114, 'bar': 514, 'zab': 1919810},
        mixinKey: mixinKey,
        wts: 1702204169,
      );

      expect(
        signed,
        'bar=514&foo=114&wts=1702204169&zab=1919810'
        '&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4',
      );
    });

    test('参数按键名升序，wts 参与排序，w_rid 追加在末尾', () {
      final query = WbiSigner.buildQuery({'b': '2', 'a': '1'}, wts: 1702204169);
      expect(query, 'a=1&b=2&wts=1702204169');
    });

    test("值里的 !'()* 在编码前剔除", () {
      expect(WbiSigner.filterReserved("a!b(c)d*e"), 'abcde');
      expect(WbiSigner.buildQuery({'k': "a!'()*b"}, wts: 1), 'k=ab&wts=1');
    });

    test('整数值的 double 不写成 1.0（与 JS String() 对齐）', () {
      expect(WbiSigner.stringify(1.0), '1');
      expect(WbiSigner.stringify(7), '7');
      expect(WbiSigner.stringify(1.5), '1.5');
      expect(WbiSigner.buildQuery({'a': 2.0}, wts: 3), 'a=2&wts=3');
    });

    test('null 值参数直接跳过', () {
      expect(WbiSigner.buildQuery({'a': null, 'b': '2'}, wts: 1), 'b=2&wts=1');
    });
  });

  group('口令缓存', () {
    WbiSigner signerWith(
      void Function() onFetch, {
      DateTime Function()? clock,
      Duration ttl = const Duration(hours: 6),
      DateTime? fetchedAt,
    }) {
      final stamp = fetchedAt ?? DateTime.utc(2026, 1, 1);
      return WbiSigner(
        fetchKeys: ({bool force = false}) async {
          onFetch();
          return WbiKeys.fromKeys(imgKey, subKey, fetchedAt: stamp);
        },
        ttl: ttl,
        clock: clock,
      );
    }

    test('6 小时内的重复调用只取一次口令', () async {
      var calls = 0;
      final signer = signerWith(
        () => calls++,
        clock: () => DateTime.utc(2026, 1, 1, 0, 30),
      );

      await signer.keys();
      await signer.keys();

      expect(calls, 1);
    });

    test('invalidate 之后重新取', () async {
      var calls = 0;
      final signer = signerWith(
        () => calls++,
        clock: () => DateTime.utc(2026, 1, 1, 0, 30),
      );

      await signer.keys();
      signer.invalidate();
      await signer.keys();

      expect(calls, 2);
    });

    test('invalidate 后的一次取口令要求来源强制重取，之后恢复缓存', () async {
      final forces = <bool>[];
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          forces.add(force);
          return WbiKeys.fromKeys(
            imgKey,
            subKey,
            fetchedAt: DateTime.utc(2026, 1, 1),
          );
        },
        clock: () => DateTime.utc(2026, 1, 1, 0, 30),
      );

      await signer.keys();
      signer.invalidate();
      await signer.keys();
      await signer.keys();

      expect(forces, [false, true]);
    });

    test('keys(force: true) 绕过缓存并把 force 传给来源', () async {
      final forces = <bool>[];
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          forces.add(force);
          return WbiKeys.fromKeys(
            imgKey,
            subKey,
            fetchedAt: DateTime.utc(2026, 1, 1),
          );
        },
        clock: () => DateTime.utc(2026, 1, 1, 0, 30),
      );

      await signer.keys();
      await signer.keys(force: true);
      await signer.keys(force: true);

      expect(forces, [false, true, true]);
    });

    test('强制刷新成功后缓存换成新口令', () async {
      const imgKey2 = '0123456789abcdef0123456789abcdef';
      var calls = 0;
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          calls++;
          return calls == 1
              ? WbiKeys.fromKeys(
                  imgKey,
                  subKey,
                  fetchedAt: DateTime.utc(2026, 1, 1),
                )
              : WbiKeys.fromKeys(
                  imgKey2,
                  subKey,
                  fetchedAt: DateTime.utc(2026, 1, 1),
                );
        },
        clock: () => DateTime.utc(2026, 1, 1, 0, 30),
      );

      final first = await signer.keys();
      final refreshed = await signer.keys(force: true);
      final cached = await signer.keys();

      expect(first.mixinKey, isNot(refreshed.mixinKey));
      expect(cached.mixinKey, refreshed.mixinKey);
      expect(calls, 2);
    });

    test('强制刷新失败后保留刷新标记，下一次仍然强制重取', () async {
      const imgKey2 = '0123456789abcdef0123456789abcdef';
      final forces = <bool>[];
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          forces.add(force);
          if (forces.length == 2) throw StateError('nav 不可用');
          return WbiKeys.fromKeys(
            forces.length == 1 ? imgKey : imgKey2,
            subKey,
            fetchedAt: DateTime.utc(2026, 1, 1),
          );
        },
        clock: () => DateTime.utc(2026, 1, 1, 0, 30),
      );

      await signer.keys();
      signer.invalidate();
      await expectLater(signer.keys(), throwsStateError);
      final refreshed = await signer.keys();

      expect(forces, [false, true, true]);
      expect(refreshed.mixinKey, WbiSigner.mixinKeyOf(imgKey2, subKey));
    });

    test('超过 ttl 后重新取（口令每日更替）', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 1, 1);
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          calls++;
          return WbiKeys.fromKeys(imgKey, subKey, fetchedAt: now);
        },
        clock: () => now,
      );

      await signer.keys();
      now = now.add(const Duration(hours: 7));
      await signer.keys();

      expect(calls, 2);
    });

    test('并发调用共享同一次请求', () async {
      var calls = 0;
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return WbiKeys.fromKeys(
            imgKey,
            subKey,
            fetchedAt: DateTime.utc(2026, 1, 1),
          );
        },
        clock: () => DateTime.utc(2026, 1, 1),
      );

      await Future.wait([signer.keys(), signer.keys(), signer.keys()]);

      expect(calls, 1);
    });

    test('取口令失败后不缓存失败结果，下次会重试', () async {
      var calls = 0;
      final signer = WbiSigner(
        fetchKeys: ({bool force = false}) async {
          calls++;
          if (calls == 1) throw StateError('nav 未返回 wbi_img');
          return WbiKeys.fromKeys(
            imgKey,
            subKey,
            fetchedAt: DateTime.utc(2026, 1, 1),
          );
        },
        clock: () => DateTime.utc(2026, 1, 1),
      );

      await expectLater(signer.keys(), throwsStateError);
      final keys = await signer.keys();

      expect(keys.mixinKey, mixinKey);
      expect(calls, 2);
    });
  });
}
