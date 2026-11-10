import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmIconButton：三档尺寸 / 命中区 / 颜色语义 / 点击与禁用 / tooltip。
void main() {
  testWidgets('sm/md/lg/xl 可视尺寸 28/34/40/44，命中区不小于 44，图标 16/20/24', (
    tester,
  ) async {
    for (final size in BmIconButtonSize.values) {
      await _pumpIconButton(
        tester,
        BmIconButton(icon: Icons.play_arrow_rounded, size: size),
      );

      final visual = switch (size) {
        BmIconButtonSize.sm => 28.0,
        BmIconButtonSize.md => 34.0,
        BmIconButtonSize.lg => 40.0,
        BmIconButtonSize.xl => 44.0,
      };
      final expectedIcon = switch (size) {
        BmIconButtonSize.sm => 16.0,
        BmIconButtonSize.xl => 24.0,
        _ => 20.0,
      };
      final expectedHit = visual < 40 ? 40.0 : visual;

      expect(
        tester.getSize(find.byType(BmIconButton)),
        Size(expectedHit, expectedHit),
        reason: '${size.name} 的命中区不小于 40',
      );
      final boxes = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(BmIconButton),
              matching: find.byType(SizedBox),
            ),
          )
          .toList();
      expect(
        boxes.any((box) => box.width == visual && box.height == visual),
        isTrue,
        reason: '${size.name} 应有 ${visual}x$visual 的可视层',
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(
        icon.size,
        expectedIcon,
        reason: '${size.name} 的图标尺寸应为 $expectedIcon',
      );
      final richText = tester.widget<RichText>(
        find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
      );
      expect(
        (richText.text as TextSpan).style?.fontSize,
        expectedIcon,
        reason: '${size.name} 的实际绘制字号应为 $expectedIcon',
      );
    }
  });

  testWidgets('hitSize 覆盖默认命中区，可视尺寸不变', (tester) async {
    await _pumpIconButton(
      tester,
      const BmIconButton(icon: Icons.close, hitSize: 44),
    );
    expect(tester.getSize(find.byType(BmIconButton)), const Size(44, 44));
    final boxes = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(BmIconButton),
            matching: find.byType(SizedBox),
          ),
        )
        .toList();
    expect(boxes.any((box) => box.width == 34 && box.height == 34), isTrue);
  });

  testWidgets('点击触发 onPressed，禁用态不响应且降到 38%', (tester) async {
    var taps = 0;
    await _pumpIconButton(
      tester,
      BmIconButton(icon: Icons.favorite_border, onPressed: () => taps++),
    );
    await tester.tap(find.byType(BmIconButton));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await _pumpIconButton(
      tester,
      const BmIconButton(icon: Icons.favorite_border),
    );
    final pressable = tester.widget<BmPressable>(find.byType(BmPressable));
    expect(pressable.enabled, isFalse);
    expect(pressable.onTap, isNull);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      BmAlpha.disabled,
    );

    await tester.tap(find.byType(BmIconButton));
    await tester.pumpAndSettle();
    expect(taps, 1, reason: '禁用态不应触发回调');
  });

  testWidgets('tooltip 非空时包 Tooltip，空字符串不包', (tester) async {
    await _pumpIconButton(
      tester,
      const BmIconButton(icon: Icons.more_horiz, tooltip: '更多'),
    );
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, '更多');

    await _pumpIconButton(
      tester,
      const BmIconButton(icon: Icons.more_horiz, tooltip: ''),
    );
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('颜色优先级：danger > active > color > textSecondary', (tester) async {
    final colors = await _pumpIconButton(
      tester,
      const BmIconButton(icon: Icons.star),
    );
    expect(_icon(tester).color, colors.textSecondary);

    await _pumpIconButton(
      tester,
      BmIconButton(icon: Icons.star, color: colors.warning),
    );
    expect(_icon(tester).color, colors.warning, reason: 'color 临时语义色只改图标');

    await _pumpIconButton(
      tester,
      BmIconButton(icon: Icons.star, color: colors.warning, active: true),
    );
    expect(_icon(tester).color, colors.accent);
    final activePressable = tester.widget<BmPressable>(
      find.byType(BmPressable),
    );
    expect(activePressable.selected, isTrue);
    expect(
      activePressable.overlayColor,
      isNull,
      reason: 'active 走 stateSelected 底，不覆盖状态层',
    );

    await _pumpIconButton(
      tester,
      BmIconButton(
        icon: Icons.star,
        color: colors.warning,
        active: true,
        danger: true,
      ),
    );
    expect(_icon(tester).color, colors.danger);
    expect(
      tester.widget<BmPressable>(find.byType(BmPressable)).overlayColor,
      colors.danger.withValues(alpha: BmAlpha.pressed),
    );
  });
}

/// 起一个只挂 [BmIconButton] 的最小页面，返回当前主题的颜色角色。
Future<BmColors> _pumpIconButton(
  WidgetTester tester,
  BmIconButton button,
) async {
  final theme = ThemeRegistry.defaultTheme.light();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: button)),
    ),
  );
  await tester.pump();
  return theme.extension<BmColors>()!;
}

Icon _icon(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));
