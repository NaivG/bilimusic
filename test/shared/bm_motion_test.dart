import 'dart:math' as math;

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/motion/spring_curve.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lucent M0 动效：时长 / 曲线 / 弹簧 / reduce motion。
void main() {
  group('BmMotion 时长', () {
    test('7 档时长 + 既有例外', () {
      expect(BmMotion.instant, Duration.zero);
      expect(BmMotion.micro, const Duration(milliseconds: 80));
      expect(BmMotion.small, const Duration(milliseconds: 120));
      expect(BmMotion.medium, const Duration(milliseconds: 180));
      expect(BmMotion.large, const Duration(milliseconds: 240));
      expect(BmMotion.xlarge, const Duration(milliseconds: 320));
      expect(BmMotion.hero, const Duration(milliseconds: 460));
      expect(BmMotion.backdrop, const Duration(milliseconds: 400));
      expect(BmMotion.sheetMax, const Duration(milliseconds: 500));
      expect(BmMotion.pageMax, const Duration(milliseconds: 300));
      expect(BmMotion.lyricScrollMax, const Duration(milliseconds: 500));
      expect(BmMotion.lyricSwitchMax, const Duration(milliseconds: 480));
      // 状态层：进场 micro、退场 small（退场不必比进场慢，但必须仍是 token）。
      expect(BmMotion.hoverIn, BmMotion.micro);
      expect(BmMotion.hoverOut, BmMotion.small);
      expect(BmMotion.pressIn, BmMotion.micro);
      expect(BmMotion.pressOut, BmMotion.small);
      expect(BmMotion.stagger, const Duration(milliseconds: 20));
      expect(BmMotion.staggerMax, 6);
    });

    test('超过 320ms 的只有弹簧收敛预算 / hero / backdrop', () {
      const limit = Duration(milliseconds: 320);
      final durations = <String, Duration>{
        'instant': BmMotion.instant,
        'micro': BmMotion.micro,
        'small': BmMotion.small,
        'medium': BmMotion.medium,
        'large': BmMotion.large,
        'xlarge': BmMotion.xlarge,
        'hero': BmMotion.hero,
        'backdrop': BmMotion.backdrop,
        'sheetMax': BmMotion.sheetMax,
        'pageMax': BmMotion.pageMax,
        'lyricScrollMax': BmMotion.lyricScrollMax,
        'lyricSwitchMax': BmMotion.lyricSwitchMax,
        'hoverIn': BmMotion.hoverIn,
        'hoverOut': BmMotion.hoverOut,
        'pressIn': BmMotion.pressIn,
        'pressOut': BmMotion.pressOut,
        'stagger': BmMotion.stagger,
      };
      final overLimit = durations.entries
          .where((entry) => entry.value > limit)
          .map((entry) => entry.key)
          .toSet();
      expect(overLimit, <String>{
        'hero',
        'backdrop',
        'sheetMax',
        'lyricScrollMax',
        'lyricSwitchMax',
      });
      // stagger 上限 6 项 = 120ms，不超过最长常规档。
      expect(
        BmMotion.stagger * BmMotion.staggerMax,
        lessThanOrEqualTo(BmMotion.small),
      );
    });

    test('曲线 / 手势常量', () {
      expect(BmMotion.standard, same(Curves.easeOutCubic));
      expect(BmMotion.exit, same(Curves.easeInCubic));
      expect(BmMotion.emphasized, same(Curves.fastOutSlowIn));
      expect(BmMotion.linear, same(Curves.linear));
      expect(BmMotion.pressScale, 0.97);
      expect(BmMotion.pageInitialVelocityFactor, 9);
      expect(BmMotion.sheetDismissVelocity, 700);
      expect(BmMotion.sheetDismissFraction, 0.3);
    });
  });

  group('BmMotion 弹簧', () {
    test('sheetSpring：mass 3 / stiffness 1000 / 阻尼比 0.8', () {
      final spring = BmMotion.sheetSpring;
      expect(spring.mass, 3);
      expect(spring.stiffness, 1000);
      expect(spring.damping, closeTo(2 * 0.8 * math.sqrt(3 * 1000), 1e-9));
    });

    test('pressSpring：mass 1 / stiffness 500 / 阻尼比 0.75', () {
      final spring = BmMotion.pressSpring;
      expect(spring.mass, 1);
      expect(spring.stiffness, 500);
      expect(spring.damping, closeTo(2 * 0.75 * math.sqrt(1 * 500), 1e-9));
    });

    test('switchSpring：mass 1 / stiffness 700 / 阻尼比 0.85', () {
      final spring = BmMotion.switchSpring;
      expect(spring.mass, 1);
      expect(spring.stiffness, 700);
      expect(spring.damping, closeTo(2 * 0.85 * math.sqrt(1 * 700), 1e-9));
    });

    test('pageSpring：300ms 时长、临界阻尼、不 overshoot', () {
      final spring = BmMotion.pageSpring;
      expect(spring.mass, 1);
      final expectedStiffness = math.pow(2 * math.pi / 0.3, 2).toDouble();
      expect(spring.stiffness, closeTo(expectedStiffness, 1e-6));
      // 临界阻尼：damping == 2 * sqrt(mass * stiffness)。
      expect(
        spring.damping,
        closeTo(2 * math.sqrt(spring.mass * spring.stiffness), 1e-9),
      );
      expect(spring.duration.inMilliseconds, closeTo(300, 1));
      expect(BmMotion.pageMax, spring.duration);

      final simulation = SpringSimulation(spring, 0, 1, 0);
      for (final t in <double>[0.0, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0]) {
        expect(
          simulation.x(t),
          lessThanOrEqualTo(1.0 + 1e-9),
          reason: 'pageSpring 在 t=$t 处不应 overshoot',
        );
      }
    });

    test('lyricScrollSpring：普通播放档 mass 1 / stiffness 190 / 阻尼比 1.1', () {
      final spring = BmMotion.lyricScrollSpring;
      expect(spring.mass, 1);
      expect(spring.stiffness, 190);
      expect(spring.damping, closeTo(2 * 1.1 * math.sqrt(190), 1e-9));
    });

    test(
      'lyricScaleSpring：lineScale 档 mass 2 / stiffness 100 / 阻尼比 0.88',
      () {
        final spring = BmMotion.lyricScaleSpring;
        expect(spring.mass, 2);
        expect(spring.stiffness, 100);
        expect(spring.damping, closeTo(2 * 0.88 * math.sqrt(200), 1e-9));
      },
    );
  });

  group('SpringCurve', () {
    final curves = <String, (SpringCurve, double)>{
      'page': (SpringCurve.page(), 0.3),
      'sheet': (SpringCurve.sheet(), 0.5),
      'press': (SpringCurve.press(), 0.2),
      'switchThumb': (SpringCurve.switchThumb(), 0.25),
      'lyricScroll': (SpringCurve.lyricScroll(), 0.5),
      'lyricLine': (SpringCurve.lyricLine(), 0.48),
    };

    for (final entry in curves.entries) {
      test('${entry.key}：端点 0 / 1，seconds=${entry.value.$2}', () {
        final curve = entry.value.$1;
        expect(curve.seconds, entry.value.$2);
        expect(curve.transform(0), closeTo(0, 1e-9));
        expect(curve.transform(1), closeTo(1, 1e-9));
        // Curve.transform 对 0 / 1 直接短路，这里再验残差收尾本身。
        expect(curve.transformInternal(0), closeTo(0, 1e-9));
        expect(curve.transformInternal(1), closeTo(1, 1e-9));
        // 中间帧有限，不出现 NaN / 无限值。
        for (final t in <double>[0.1, 0.25, 0.5, 0.75, 0.9]) {
          expect(curve.transform(t).isFinite, isTrue, reason: 't=$t');
        }
      });
    }

    test('page：初速 9 × 距离/秒，300ms 窗口内单调收束', () {
      final curve = SpringCurve.page();
      expect(curve.initialVelocity, BmMotion.pageInitialVelocityFactor);
      expect(curve.seconds, closeTo(0.3, 1e-9));
      // 初速进场：窗口前 1/10 就走完 1/4 以上，不是从静止加速。
      expect(curve.transform(0.1), greaterThan(0.25));
      // 全窗口单调（临界阻尼 + 残差线性收尾，不 overshoot、不回弹）。
      var previous = 0.0;
      for (var i = 1; i <= 30; i++) {
        final value = curve.transform(i / 30);
        expect(value, greaterThanOrEqualTo(previous));
        expect(value, lessThanOrEqualTo(1.0));
        previous = value;
      }
    });

    test('seconds 必须为正（0 / 负数触发断言）', () {
      expect(
        () => SpringCurve(BmMotion.pageSpring, seconds: 0),
        throwsAssertionError,
      );
      expect(
        () => SpringCurve(BmMotion.pageSpring, seconds: -0.1),
        throwsAssertionError,
      );
    });
  });

  group('reduce motion', () {
    Widget probe({bool mediaDisable = false, bool? scope}) {
      Widget child = const SizedBox(key: Key('motion-probe'));
      if (scope != null) {
        child = BmMotionScope(reduceMotion: scope, child: child);
      }
      return MediaQuery(
        data: MediaQueryData(disableAnimations: mediaDisable),
        child: child,
      );
    }

    testWidgets('默认不降级：motionDuration / fadeDuration / motionCurve 原样返回', (
      tester,
    ) async {
      await tester.pumpWidget(probe());
      final context = tester.element(find.byKey(const Key('motion-probe')));
      expect(BmMotionScope.maybeReduceMotionOf(context), isNull);
      expect(reduceMotionOf(context), isFalse);
      expect(motionDuration(context, BmMotion.xlarge), BmMotion.xlarge);
      expect(fadeDuration(context, BmMotion.xlarge), BmMotion.xlarge);
      expect(motionCurve(context, BmMotion.standard), same(BmMotion.standard));
    });

    testWidgets('MediaQuery.disableAnimations 生效', (tester) async {
      await tester.pumpWidget(probe(mediaDisable: true));
      final context = tester.element(find.byKey(const Key('motion-probe')));
      expect(reduceMotionOf(context), isTrue);
      expect(motionDuration(context, BmMotion.large), Duration.zero);
      expect(motionDuration(context, BmMotion.instant), Duration.zero);
      expect(motionCurve(context, BmMotion.standard), same(BmMotion.linear));
    });

    testWidgets('BmMotionScope(true) 优先于未降级的 MediaQuery', (tester) async {
      await tester.pumpWidget(probe(scope: true));
      final context = tester.element(find.byKey(const Key('motion-probe')));
      expect(BmMotionScope.maybeReduceMotionOf(context), isTrue);
      expect(reduceMotionOf(context), isTrue);
      expect(motionDuration(context, BmMotion.large), Duration.zero);
    });

    testWidgets('BmMotionScope(false) 覆盖 MediaQuery.disableAnimations', (
      tester,
    ) async {
      await tester.pumpWidget(probe(mediaDisable: true, scope: false));
      final context = tester.element(find.byKey(const Key('motion-probe')));
      expect(BmMotionScope.maybeReduceMotionOf(context), isFalse);
      expect(reduceMotionOf(context), isFalse);
      expect(motionDuration(context, BmMotion.large), BmMotion.large);
      expect(motionCurve(context, BmMotion.standard), same(BmMotion.standard));
    });

    testWidgets('fadeDuration 最多保留 120ms', (tester) async {
      await tester.pumpWidget(probe(mediaDisable: true));
      final context = tester.element(find.byKey(const Key('motion-probe')));
      final durations = <Duration>[
        BmMotion.instant,
        BmMotion.micro,
        BmMotion.small,
        BmMotion.medium,
        BmMotion.large,
        BmMotion.xlarge,
        BmMotion.hero,
        BmMotion.backdrop,
        BmMotion.sheetMax,
      ];
      for (final duration in durations) {
        final faded = fadeDuration(context, duration);
        expect(
          faded,
          lessThanOrEqualTo(BmMotion.small),
          reason: 'fadeDuration($duration) 不能超过 120ms',
        );
        expect(faded, duration <= BmMotion.small ? duration : BmMotion.small);
      }
      // 非降级时原样返回，不裁剪。
      await tester.pumpWidget(probe());
      final normal = tester.element(find.byKey(const Key('motion-probe')));
      expect(fadeDuration(normal, BmMotion.hero), BmMotion.hero);
    });
  });
}
