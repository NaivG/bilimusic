import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/features/lan_sync/services/lan_sync_service.dart';

void main() {
  const secret =
      '0123456789abcdef0123456789abcdef'
      '0123456789abcdef0123456789abcdef';

  group('LanSyncMode 对外暴露面', () {
    test('off 不监听连接', () {
      expect(LanSyncMode.off.acceptsConnections, isFalse);
    });

    test('只有 private 允许出示配对 token', () {
      expect(LanSyncMode.private.exposesPairingToken, isTrue);
      expect(LanSyncMode.public.exposesPairingToken, isFalse);
      expect(LanSyncMode.off.exposesPairingToken, isFalse);
    });

    test('非 off 模式监听连接，但仍按模式区分配对能力', () {
      expect(LanSyncMode.private.acceptsConnections, isTrue);
      expect(LanSyncMode.public.acceptsConnections, isTrue);
      expect(LanSyncMode.public.acceptsPrivate, isFalse);
      expect(LanSyncMode.private.acceptsPrivate, isTrue);
    });
  });

  group('hello 凭据策略', () {
    test('私有模式且对端已配对才携带本机 token', () {
      expect(
        LanSyncService.helloTokenFor(
          LanSyncMode.private,
          peerPaired: true,
          selfToken: secret,
        ),
        secret,
      );
    });

    test('公共/关闭模式不出示 token', () {
      expect(
        LanSyncService.helloTokenFor(
          LanSyncMode.public,
          peerPaired: true,
          selfToken: secret,
        ),
        isNull,
      );
      expect(
        LanSyncService.helloTokenFor(
          LanSyncMode.off,
          peerPaired: true,
          selfToken: secret,
        ),
        isNull,
      );
    });

    test('首次配对（对端未配对）不出示 token', () {
      expect(
        LanSyncService.helloTokenFor(
          LanSyncMode.private,
          peerPaired: false,
          selfToken: secret,
        ),
        isNull,
      );
      expect(
        LanSyncService.helloTokenFor(
          LanSyncMode.private,
          peerPaired: true,
          selfToken: '',
        ),
        isNull,
      );
    });
  });
}
