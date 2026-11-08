import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmPressable：hover / pressed / selected / disabled / reduce motion。
void main() {
  // 测试环境的 defaultTargetPlatform 是移动端，FocusManager 默认按 touch
  // 处理，hover 高亮不会出现；这里模拟桌面鼠标交互。
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('hover → stateHover，按下 → statePressed，抬起回 hover 并触发 onTap', (
    tester,
  ) async {
    var taps = 0;
    final colors = await _pumpPressable(tester, onTap: () => taps++);
    final center = tester.getCenter(find.byType(BmPressable));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    await mouse.moveTo(center);
    await tester.pumpAndSettle();
    expect(_overlayColor(tester), colors.stateHover);

    await mouse.down(center);
    await tester.pump();
    expect(_overlayColor(tester), colors.statePressed);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      BmMotion.pressScale,
      reason: '按压时应按 pressScale 缩放',
    );

    await mouse.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(_overlayColor(tester), colors.stateHover);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);

    // 移出后状态层完全消失。
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(_overlayColor(tester), isNull);
  });

  testWidgets('selected → stateSelected', (tester) async {
    final colors = await _pumpPressable(tester, selected: true, onTap: () {});
    expect(_overlayColor(tester), colors.stateSelected);
  });

  testWidgets('disabled 不触发 onTap，也不画状态层', (tester) async {
    var taps = 0;
    await _pumpPressable(tester, enabled: false, onTap: () => taps++);
    expect(_overlayColor(tester), isNull);
    // 禁用态统一 38% 透明度
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      BmAlpha.disabled,
    );

    await tester.tap(find.byType(BmPressable));
    await tester.pumpAndSettle();
    expect(taps, 0);

    final center = tester.getCenter(find.byType(BmPressable));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(center);
    await tester.pumpAndSettle();
    expect(_overlayColor(tester), isNull);
  });

  testWidgets('reduce motion 下状态层 / 缩放时长归零', (tester) async {
    await _pumpPressable(tester, reduceMotion: true, onTap: () {});
    expect(_containerDuration(tester), Duration.zero);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
  });

  testWidgets('未降级时静息态走 120ms', (tester) async {
    await _pumpPressable(tester, onTap: () {});
    expect(_containerDuration(tester), BmMotion.small);
  });
}

/// 起一个只挂 BmPressable 的最小页面，返回当前主题的颜色角色。
Future<BmColors> _pumpPressable(
  WidgetTester tester, {
  VoidCallback? onTap,
  bool selected = false,
  bool enabled = true,
  bool reduceMotion = false,
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  final colors = theme.extension<BmColors>()!;
  Widget body = Center(
    child: BmPressable(
      onTap: onTap,
      selected: selected,
      enabled: enabled,
      pressScale: BmMotion.pressScale,
      child: const SizedBox(width: 160, height: 48),
    ),
  );
  if (reduceMotion) {
    body = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: body,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
  return colors;
}

/// 读 AnimatedContainer 当前的目标底色（状态层）。
Color? _overlayColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  final decoration = container.decoration;
  expect(decoration, isA<BoxDecoration>());
  return (decoration! as BoxDecoration).color;
}

Duration _containerDuration(WidgetTester tester) {
  return tester
      .widget<AnimatedContainer>(find.byType(AnimatedContainer))
      .duration;
}
