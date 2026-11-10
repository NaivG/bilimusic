import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/chrome/bm_nav_row.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmNavRow：行高 / 选中条 / 选中底 / 图标文字颜色 / 回调。
void main() {
  testWidgets('默认 44 高，内容左右 12、图标与文字间距 12，body 15/21 单行省略', (tester) async {
    final colors = await _pumpRow(tester);

    final size = tester.getSize(find.byType(BmNavRow));
    expect(size.height, BmTokens.navRowHeight);
    expect(size.width, 240);

    final rowLeft = tester.getTopLeft(find.byType(BmNavRow)).dx;
    final icon = find.byIcon(Icons.home_outlined);
    final title = find.text('首页');
    expect(tester.getTopLeft(icon).dx - rowLeft, BmTokens.s3);
    expect(
      tester.getTopLeft(title).dx - tester.getTopRight(icon).dx,
      BmTokens.s3,
    );

    final textStyle = _textStyle(tester);
    expect(textStyle.fontSize, 15);
    expect(textStyle.height, closeTo(21 / 15, 1e-9));
    expect(textStyle.color, colors.textSecondary);

    final text = tester.widget<Text>(title);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('选中：accentSoft 胶囊底、文字 textPrimary、图标 accentDeep', (tester) async {
    final colors = await _pumpRow(tester, selected: true);

    // BmPressable 的选中状态层 = accentSoftStrong（18%）。
    final overlay = tester.widget<AnimatedContainer>(_pressableOverlay(colors));
    final overlayColor = (overlay.decoration! as BoxDecoration).color;
    expect(overlayColor, colors.accentSoftStrong);
    expect(overlayColor!.a, closeTo(BmAlpha.selectedStrong, 1e-9));

    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.home)).color,
      colors.accentDeep,
    );
    expect(_textStyle(tester).color, colors.textPrimary);
  });

  testWidgets('未选中：无选中底，图标/文字 textSecondary', (tester) async {
    final colors = await _pumpRow(tester);

    expect(_pressableOverlay(colors), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color,
      colors.textSecondary,
    );
    expect(_textStyle(tester).color, colors.textSecondary);
    expect(find.byIcon(Icons.home), findsNothing);
  });

  testWidgets('点击与长按分别触发 onTap / onLongPress', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await _pumpRow(
      tester,
      onTap: () => taps++,
      onLongPress: () => longPresses++,
    );

    await tester.tap(find.byType(BmNavRow));
    await tester.pump();
    expect(taps, 1);

    await tester.longPress(find.byType(BmNavRow));
    await tester.pumpAndSettle();
    expect(longPresses, 1);
  });

  testWidgets('自定义高度 / 内边距 / trailing', (tester) async {
    await _pumpRow(
      tester,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s4),
      trailing: const Icon(Icons.more_horiz, size: BmTokens.iconMenu),
    );

    expect(tester.getSize(find.byType(BmNavRow)).height, 48);

    final rowLeft = tester.getTopLeft(find.byType(BmNavRow)).dx;
    final rowRight = tester.getTopRight(find.byType(BmNavRow)).dx;
    expect(
      tester.getTopLeft(find.byIcon(Icons.home_outlined)).dx - rowLeft,
      BmTokens.s4,
    );
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(
      tester.getTopRight(find.byIcon(Icons.more_horiz)).dx,
      rowRight - BmTokens.s4,
    );
  });

  testWidgets('文字颜色 120ms，reduce motion 时归零', (tester) async {
    await _pumpRow(tester, selected: true);
    expect(_animatedTextStyle(tester).duration, BmMotion.small);

    await _pumpRow(tester, selected: true, reduceMotion: true);
    expect(_animatedTextStyle(tester).duration, Duration.zero);
  });

  testWidgets('focusNode 接线：requestFocus 后获得焦点', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpRow(tester, focusNode: focusNode);

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasPrimaryFocus, isTrue);
  });
}

/// 起一个挂 BmNavRow 的最小页面（固定宽 240），返回当前主题的颜色角色。
Future<BmColors> _pumpRow(
  WidgetTester tester, {
  bool selected = false,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  IconData icon = Icons.home_outlined,
  IconData? activeIcon = Icons.home,
  String title = '首页',
  Widget? trailing,
  double height = BmTokens.navRowHeight,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: BmTokens.s3,
  ),
  FocusNode? focusNode,
  bool autofocus = false,
  bool reduceMotion = false,
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  final colors = theme.extension<BmColors>()!;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) {
              Widget row = SizedBox(
                width: 240,
                child: BmNavRow(
                  icon: icon,
                  activeIcon: activeIcon,
                  title: title,
                  trailing: trailing,
                  selected: selected,
                  onTap: onTap,
                  onLongPress: onLongPress,
                  height: height,
                  padding: padding,
                  focusNode: focusNode,
                  autofocus: autofocus,
                ),
              );
              if (reduceMotion) {
                row = MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: true),
                  child: row,
                );
              }
              return row;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return colors;
}

Finder _pressableOverlay(BmColors colors) {
  return find.descendant(
    of: find.byType(BmPressable),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color ==
              colors.accentSoftStrong,
    ),
  );
}

AnimatedDefaultTextStyle _animatedTextStyle(WidgetTester tester) {
  return tester.widget<AnimatedDefaultTextStyle>(
    find.descendant(
      of: find.byType(BmNavRow),
      matching: find.byType(AnimatedDefaultTextStyle),
    ),
  );
}

TextStyle _textStyle(WidgetTester tester) {
  return _animatedTextStyle(tester).style;
}
