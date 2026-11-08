import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lucent P1 菜单原语：行四态 / 浮层面 / 入场动画。
void main() {
  group('BmMenuRow', () {
    testWidgets('普通态：行高取 BmTokens.menuRow，标题用 textPrimary', (tester) async {
      final colors = await _pump(tester, BmMenuRow(title: '下一首', onTap: () {}));

      final rowBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(BmMenuRow),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == BmTokens.menuRow,
          ),
        ),
      );
      expect(rowBox.height, BmTokens.menuRow);
      expect(tester.getSize(find.byType(BmMenuRow)).height, BmTokens.menuRow);

      final title = tester.widget<Text>(find.text('下一首'));
      expect(title.style!.color, colors.textPrimary);
      expect(title.style!.fontSize, 15);
    });

    testWidgets('selected：状态层底色等于 accentSoft', (tester) async {
      final colors = await _pump(
        tester,
        BmMenuRow(title: '已选中', selected: true, onTap: () {}),
      );

      final decoration = _rowDecoration(tester);
      expect(decoration.color, colors.accentSoft);
      expect(colors.accentSoft, colors.stateSelected);
    });

    testWidgets('destructive：文字与行首图标都改 danger', (tester) async {
      final colors = await _pump(
        tester,
        BmMenuRow(
          title: '删除',
          leading: const Icon(Icons.delete_outline),
          destructive: true,
          onTap: () {},
        ),
      );

      expect(tester.widget<Text>(find.text('删除')).style!.color, colors.danger);

      final iconTheme = tester.widget<IconTheme>(
        find
            .descendant(
              of: find.byType(BmMenuRow),
              matching: find.byType(IconTheme),
            )
            .first,
      );
      expect(iconTheme.data.color, colors.danger);
      expect(iconTheme.data.size, BmTokens.iconMenu);
    });

    testWidgets('disabled：点击不触发回调，整行 38% 透明', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        BmMenuRow(title: '不可用', enabled: false, onTap: () => taps++),
      );

      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(BmMenuRow),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, BmAlpha.disabled);

      await tester.tap(find.byType(BmMenuRow));
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('普通项点击触发回调', (tester) async {
      var taps = 0;
      await _pump(tester, BmMenuRow(title: '播放', onTap: () => taps++));

      await tester.tap(find.byType(BmMenuRow));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('shortcut / showChevron 渲染出对应文本与箭头', (tester) async {
      final colors = await _pump(
        tester,
        const BmMenuRow(
          title: '重命名',
          leading: Icon(Icons.edit_outlined),
          shortcut: 'F2',
          showChevron: true,
        ),
      );

      expect(find.text('F2'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('F2')).style!.color,
        colors.textTertiary,
      );
      expect(tester.widget<Text>(find.text('F2')).style!.fontSize, 12);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('height 可覆盖默认 token', (tester) async {
      await _pump(
        tester,
        const BmMenuRow(title: '触屏行', height: BmTokens.touchScreen),
      );
      expect(
        tester.getSize(find.byType(BmMenuRow)).height,
        BmTokens.touchScreen,
      );
    });
  });

  group('BmMenuSurface', () {
    testWidgets('floating 底 + r14 圆角 + 0.5 hairline 边', (tester) async {
      final colors = await _pump(
        tester,
        const BmMenuSurface(child: SizedBox(width: 200, height: 100)),
      );

      final decoration = _surfaceDecoration(tester);
      expect(decoration.color, colors.floating);
      expect(decoration.borderRadius, BmTokens.r14All);

      final border = decoration.border! as Border;
      expect(border.top.color, colors.hairline);
      expect(border.top.width, 0.5);
      expect(decoration.boxShadow, hasLength(1));
    });

    testWidgets('entrance 非空时外包 BmMenuEntrance', (tester) async {
      await _pump(
        tester,
        const BmMenuSurface(
          entrance: BmMenuEntranceKind.submenu,
          child: SizedBox(width: 200, height: 100),
        ),
      );
      expect(find.byType(BmMenuEntrance), findsOneWidget);
    });
  });

  group('BmMenuEntrance', () {
    testWidgets('reduce motion：挂载第一帧即终态', (tester) async {
      await _pump(
        tester,
        const BmMenuEntrance(
          child: SizedBox(key: Key('entrance-child'), width: 120, height: 80),
        ),
        reduceMotion: true,
      );

      // 不 pumpAndSettle：第一帧就必须是终态。当前实现直接返回 child，
      // 不建动画层；若以后改成建终态层，这里仍要求 scale / opacity 都是终值。
      expect(_entranceScales(tester), everyElement(closeTo(1.0, 1e-6)));
      expect(_entranceOpacityValues(tester), everyElement(1.0));
      expect(find.byKey(const Key('entrance-child')), findsOneWidget);
    });

    testWidgets('非 reduce motion：首帧 0.96 / 0，中间帧过渡，settle 后 1', (tester) async {
      await _pump(
        tester,
        const BmMenuEntrance(child: SizedBox(width: 120, height: 80)),
      );

      // 首帧：从 0.96 起，全透明。
      expect(_entranceScale(tester), closeTo(0.96, 1e-6));
      expect(_entranceOpacity(tester), 0);

      // 中间帧：既不是起点也不是终点，证明动画真的在走。
      await tester.pump(const Duration(milliseconds: 60));
      final midScale = _entranceScale(tester);
      expect(midScale, greaterThan(0.96));
      expect(midScale, lessThan(1.0));
      expect(_entranceOpacity(tester), inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(_entranceScale(tester), closeTo(1.0, 1e-6));
      expect(_entranceOpacity(tester), 1.0);
    });

    testWidgets('submenu 入场：水平位移 8px → 0，不缩放', (tester) async {
      await _pump(
        tester,
        const BmMenuEntrance(
          kind: BmMenuEntranceKind.submenu,
          child: SizedBox(width: 120, height: 80),
        ),
      );

      expect(_entranceTransforms(tester), findsOneWidget);
      expect(_entranceScale(tester), closeTo(1.0, 1e-6));
      expect(_translationX(tester), closeTo(-BmTokens.s2, 1e-6));

      await tester.pumpAndSettle();
      expect(_translationX(tester), closeTo(0, 1e-6));
    });
  });
}

/// 起一个最小页面；[reduceMotion] 包的是内容而不是 MaterialApp ——
/// MaterialApp 由根 View 注入 MediaQuery，外层包会被覆盖。
Future<BmColors> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  Widget content = Center(child: child);
  if (reduceMotion) {
    content = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: content,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: content),
    ),
  );
  return theme.extension<BmColors>()!;
}

BoxDecoration _rowDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(BmMenuRow),
      matching: find.byType(AnimatedContainer),
    ),
  );
  final decoration = container.decoration;
  expect(decoration, isA<BoxDecoration>());
  return decoration! as BoxDecoration;
}

BoxDecoration _surfaceDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(BmMenuSurface),
          matching: find.byType(Container),
        )
        .first,
  );
  final decoration = container.decoration;
  expect(decoration, isA<BoxDecoration>());
  return decoration! as BoxDecoration;
}

Finder _entranceTransforms(WidgetTester tester) {
  return find.descendant(
    of: find.byType(BmMenuEntrance),
    matching: find.byType(Transform),
  );
}

Finder _entranceOpacities(WidgetTester tester) {
  return find.descendant(
    of: find.byType(BmMenuEntrance),
    matching: find.byType(Opacity),
  );
}

double _entranceScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(_entranceTransforms(tester));
  // 矩阵是 3D 齐次坐标：Z 轴恒为 1，getMaxScaleOnAxis 会退化成 1，
  // 这里直接读 m00 取 2D 缩放。
  return transform.transform.storage[0];
}

List<double> _entranceScales(WidgetTester tester) {
  return tester
      .widgetList<Transform>(_entranceTransforms(tester))
      .map((transform) => transform.transform.storage[0])
      .toList();
}

List<double> _entranceOpacityValues(WidgetTester tester) {
  return tester
      .widgetList<Opacity>(_entranceOpacities(tester))
      .map((opacity) => opacity.opacity)
      .toList();
}

double _translationX(WidgetTester tester) {
  final transform = tester.widget<Transform>(_entranceTransforms(tester));
  return transform.transform.storage[12];
}

double _entranceOpacity(WidgetTester tester) {
  return tester.widget<Opacity>(_entranceOpacities(tester)).opacity;
}
