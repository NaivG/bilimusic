import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/chrome/bm_nav_bar.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmNavBar：高度 / safe area / 选中色 / 颜色过渡 / 回调。
void main() {
  const items = <BmNavBarItem>[
    BmNavBarItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: '首页',
    ),
    BmNavBarItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore,
      label: '发现',
    ),
    BmNavBarItem(icon: Icons.settings_outlined, label: '设置'),
  ];

  testWidgets('高度 56，表面顶部 hairline + 模糊', (tester) async {
    final colors = await _pumpNavBar(tester, items: items);

    expect(tester.getSize(find.byType(BmNavBar)).height, BmTokens.navBarHeight);

    final border = _decoration(tester, foreground: true).border! as Border;
    expect(border.top.color, colors.hairline);
    expect(border.top.width, BmTokens.hairlineWidth);
    expect(border.bottom, BorderSide.none);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);

    expect(
      find.descendant(
        of: find.byType(BmNavBar),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  testWidgets('底部 safe area 计入高度，top safe area 不计', (tester) async {
    await _pumpNavBar(
      tester,
      items: items,
      padding: const EdgeInsets.only(top: 20, bottom: 24),
    );

    expect(
      tester.getSize(find.byType(BmNavBar)).height,
      BmTokens.navBarHeight + 24,
    );
  });

  testWidgets('选中项用 activeIcon + accent，未选中用 textSecondary', (tester) async {
    final colors = await _pumpNavBar(tester, items: items, selectedIndex: 1);

    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.explore)).color,
      colors.accent,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color,
      colors.textSecondary,
    );

    final selectedLabel = tester.widget<Text>(find.text('发现'));
    expect(selectedLabel.style!.color, colors.accent);
    expect(selectedLabel.style!.fontSize, 11);
    expect(selectedLabel.style!.height, closeTo(14 / 11, 1e-9));

    expect(
      tester.widget<Text>(find.text('首页')).style!.color,
      colors.textSecondary,
    );
  });

  testWidgets('无 activeIcon 时选中沿用 icon', (tester) async {
    final colors = await _pumpNavBar(tester, items: items, selectedIndex: 2);

    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.settings_outlined)).color,
      colors.accent,
    );
  });

  testWidgets('点击回调选中下标', (tester) async {
    var selected = -1;
    await _pumpNavBar(
      tester,
      items: items,
      onSelected: (index) => selected = index,
    );

    await tester.tap(find.text('发现'));
    await tester.pump();
    expect(selected, 1);

    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(selected, 2);
  });

  testWidgets('颜色过渡 80ms，reduce motion 时归零', (tester) async {
    await _pumpNavBar(tester, items: items);

    final builder = tester.widget<TweenAnimationBuilder<Color?>>(
      find.ancestor(
        of: find.byIcon(Icons.home),
        matching: find.byType(TweenAnimationBuilder<Color?>),
      ),
    );
    expect(builder.duration, BmMotion.micro);
    expect(builder.curve, BmMotion.linear);

    await _pumpNavBar(tester, items: items, reduceMotion: true);
    final reduced = tester.widget<TweenAnimationBuilder<Color?>>(
      find.ancestor(
        of: find.byIcon(Icons.home),
        matching: find.byType(TweenAnimationBuilder<Color?>),
      ),
    );
    expect(reduced.duration, Duration.zero);
  });

  testWidgets('blur=false 时不挂 BackdropFilter，底色换成 chromeOpaque', (
    tester,
  ) async {
    final colors = await _pumpNavBar(tester, items: items, blur: false);

    expect(
      find.descendant(
        of: find.byType(BmNavBar),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(_background(tester).color, colors.chromeOpaque);
  });
}

/// 起一个挂 BmNavBar 的最小页面，返回当前主题的颜色角色。
Future<BmColors> _pumpNavBar(
  WidgetTester tester, {
  required List<BmNavBarItem> items,
  int selectedIndex = 0,
  ValueChanged<int>? onSelected,
  bool blur = true,
  bool reduceMotion = false,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  final colors = theme.extension<BmColors>()!;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final Widget navBar = BmNavBar(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: onSelected ?? (_) {},
              blur: blur,
            );
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(padding: padding, disableAnimations: reduceMotion),
              child: navBar,
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return colors;
}

Finder _decorationFinder({required bool foreground}) {
  return find.descendant(
    of: find.byType(BmChromeSurface),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.position ==
              (foreground
                  ? DecorationPosition.foreground
                  : DecorationPosition.background),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester, {required bool foreground}) {
  final box = tester.widget<DecoratedBox>(
    _decorationFinder(foreground: foreground),
  );
  return box.decoration as BoxDecoration;
}

ColoredBox _background(WidgetTester tester) {
  return tester.widget<ColoredBox>(
    find.descendant(
      of: find.byType(BmNavBar),
      matching: find.byType(ColoredBox),
    ),
  );
}
