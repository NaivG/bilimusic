import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lan_sync/logic/resolve_deduper.dart';

/// 假定时器：手动触发超时，测试不真正等待 5 秒。
class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }

  /// 模拟超时到期。
  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }
}

void main() {
  late List<_FakeTimer> timers;

  ResolveDeduper buildDeduper() => ResolveDeduper(
    timeout: const Duration(seconds: 5),
    timerFactory: (duration, callback) {
      final timer = _FakeTimer(duration, callback);
      timers.add(timer);
      return timer;
    },
  );

  setUp(() {
    timers = <_FakeTimer>[];
  });

  group('ResolveDeduper', () {
    test('同一服务在途期间不重复放行，其它服务不受影响', () {
      final deduper = buildDeduper();

      expect(deduper.tryBegin('cam\u0000_bilimusic-sync._tcp'), isTrue);
      expect(deduper.tryBegin('cam\u0000_bilimusic-sync._tcp'), isFalse);
      expect(deduper.inFlightCount, 1);
      expect(deduper.isInFlight('cam\u0000_bilimusic-sync._tcp'), isTrue);

      // 不同服务互不影响。
      expect(deduper.tryBegin('tv\u0000_bilimusic-sync._tcp'), isTrue);
      expect(deduper.inFlightCount, 2);
      expect(timers, hasLength(2));
      expect(timers.first.duration, const Duration(seconds: 5));
    });

    test('收到终态事件后清除占位，允许重新解析', () {
      final deduper = buildDeduper();
      final key = 'cam\u0000_bilimusic-sync._tcp';
      deduper.tryBegin(key);

      deduper.complete(key);

      expect(deduper.isInFlight(key), isFalse);
      expect(timers.single.isActive, isFalse, reason: '清除时应取消超时定时器');
      expect(deduper.tryBegin(key), isTrue);
    });

    test('清除不存在的服务键不报错', () {
      final deduper = buildDeduper();

      expect(() => deduper.complete('missing'), returnsNormally);
      expect(deduper.inFlightCount, 0);
    });

    test('超时兜底清除，避免服务永久卡在在途状态', () {
      final deduper = buildDeduper();
      final key = 'cam\u0000_bilimusic-sync._tcp';
      deduper.tryBegin(key);
      expect(deduper.tryBegin(key), isFalse);

      timers.single.fire();

      expect(deduper.isInFlight(key), isFalse);
      expect(deduper.tryBegin(key), isTrue);
    });

    test('clear 取消全部在途占位（停止发现时调用）', () {
      final deduper = buildDeduper();
      deduper.tryBegin('a');
      deduper.tryBegin('b');

      deduper.clear();

      expect(deduper.inFlightCount, 0);
      expect(timers.every((timer) => !timer.isActive), isTrue);
      expect(deduper.tryBegin('a'), isTrue);
    });

    test('超时只清除自己那一个服务键', () {
      final deduper = buildDeduper();
      final cam = 'cam\u0000_bilimusic-sync._tcp';
      final tv = 'tv\u0000_bilimusic-sync._tcp';
      deduper.tryBegin(cam);
      deduper.tryBegin(tv);

      timers.first.fire();

      expect(deduper.isInFlight(cam), isFalse);
      expect(deduper.isInFlight(tv), isTrue);
      expect(deduper.inFlightCount, 1);
    });
  });
}
