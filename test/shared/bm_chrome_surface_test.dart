import 'dart:ui' show ImageFilter;

import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmChromeSurface：贴边 / 浮块材质、模糊开关与描边阴影。
void main() {
  group('BmChromeSurface', () {
    testWidgets('浮块：14 圆角 + 四边 hairline + shadow + chrome 底 + 24 模糊', (
      tester,
    ) async {
      final colors = await _pumpSurface(tester, floating: true);

      // 底色：chrome + 24 高斯模糊。
      expect(_background(tester).color, colors.chrome);
      final backdrop = tester.widget<BackdropFilter>(_backdropFinder());
      expect(
        backdrop.filter,
        ImageFilter.blur(
          sigmaX: BmTokens.chromeBlurSigma,
          sigmaY: BmTokens.chromeBlurSigma,
        ),
      );

      // 描边：四边 0.5px hairline，14 圆角。
      final borderDecoration = _decoration(tester, foreground: true);
      expect(borderDecoration.borderRadius, BmTokens.r14All);
      final border = borderDecoration.border! as Border;
      for (final side in <BorderSide>[
        border.top,
        border.right,
        border.bottom,
        border.left,
      ]) {
        expect(side.color, colors.hairline);
        expect(side.width, BmTokens.hairlineWidth);
      }

      // 阴影：shadow / 24 blur / 下移 8。
      final shadowDecoration = _decoration(tester, foreground: false);
      expect(shadowDecoration.borderRadius, BmTokens.r14All);
      final shadow = shadowDecoration.boxShadow!.single;
      expect(shadow.color, colors.shadow);
      expect(shadow.blurRadius, BmTokens.s6);
      expect(shadow.offset, const Offset(0, BmTokens.s2));
    });

    testWidgets('贴边：直角，只在指定边画 hairline', (tester) async {
      final colors = await _pumpSurface(
        tester,
        edges: const <BmChromeEdge>{BmChromeEdge.top},
      );

      final decoration = _decoration(tester, foreground: true);
      expect(decoration.borderRadius, BorderRadius.zero);
      final border = decoration.border! as Border;
      expect(border.top.color, colors.hairline);
      expect(border.top.width, BmTokens.hairlineWidth);
      expect(border.bottom, BorderSide.none);
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);

      // 贴边栏不投影。
      expect(_decoration(tester, foreground: false).boxShadow, isNull);
    });

    testWidgets('贴边默认只画 bottom', (tester) async {
      await _pumpSurface(tester);

      final border = _decoration(tester, foreground: true).border! as Border;
      expect(border.bottom.width, BmTokens.hairlineWidth);
      expect(border.top, BorderSide.none);
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);
    });

    testWidgets('贴边可同时画 left + right', (tester) async {
      final colors = await _pumpSurface(
        tester,
        edges: const <BmChromeEdge>{BmChromeEdge.left, BmChromeEdge.right},
      );

      final border = _decoration(tester, foreground: true).border! as Border;
      expect(border.left.color, colors.hairline);
      expect(border.right.color, colors.hairline);
      expect(border.top, BorderSide.none);
      expect(border.bottom, BorderSide.none);
    });

    testWidgets('浮块忽略 edges，四边都有描边', (tester) async {
      await _pumpSurface(
        tester,
        floating: true,
        edges: const <BmChromeEdge>{BmChromeEdge.top},
      );

      final border = _decoration(tester, foreground: true).border! as Border;
      expect(border.top.width, BmTokens.hairlineWidth);
      expect(border.right.width, BmTokens.hairlineWidth);
      expect(border.bottom.width, BmTokens.hairlineWidth);
      expect(border.left.width, BmTokens.hairlineWidth);
    });

    testWidgets('blur=false：用 chromeOpaque 且树里没有 BackdropFilter', (
      tester,
    ) async {
      final colors = await _pumpSurface(tester, blur: false);

      expect(_backdropFinder(), findsNothing);
      expect(_background(tester).color, colors.chromeOpaque);
    });

    testWidgets('blur=true 时 BackdropFilter 被裁剪层包住，描边/阴影在裁剪层外', (tester) async {
      await _pumpSurface(tester, floating: true);

      final clip = find.byType(ClipRRect);
      expect(
        find.ancestor(of: find.byType(BackdropFilter), matching: clip),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: clip,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.foreground,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: clip,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.background,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('padding 内缩内容', (tester) async {
      await _pumpSurface(
        tester,
        padding: const EdgeInsets.all(BmTokens.s3),
        child: const SizedBox(
          key: ValueKey<String>('chrome-content'),
          width: 100,
          height: 40,
        ),
      );

      expect(tester.getSize(find.byType(BmChromeSurface)), const Size(124, 64));
      final surfaceTopLeft = tester.getTopLeft(find.byType(BmChromeSurface));
      final contentTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('chrome-content')),
      );
      expect(
        contentTopLeft - surfaceTopLeft,
        const Offset(BmTokens.s3, BmTokens.s3),
      );
    });
  });
}

/// 起一个只挂 BmChromeSurface 的最小页面，返回当前主题的颜色角色。
Future<BmColors> _pumpSurface(
  WidgetTester tester, {
  bool floating = false,
  bool blur = true,
  Set<BmChromeEdge> edges = const <BmChromeEdge>{BmChromeEdge.bottom},
  EdgeInsetsGeometry? padding,
  Widget child = const SizedBox(width: 160, height: 56),
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  final colors = theme.extension<BmColors>()!;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: BmChromeSurface(
            floating: floating,
            blur: blur,
            edges: edges,
            padding: padding,
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return colors;
}

Finder _surfaceDescendant(Finder matching) {
  return find.descendant(of: find.byType(BmChromeSurface), matching: matching);
}

Finder _backdropFinder() {
  return _surfaceDescendant(find.byType(BackdropFilter));
}

ColoredBox _background(WidgetTester tester) {
  return tester.widget<ColoredBox>(_surfaceDescendant(find.byType(ColoredBox)));
}

BoxDecoration _decoration(WidgetTester tester, {required bool foreground}) {
  final box = tester.widget<DecoratedBox>(
    _surfaceDescendant(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.position ==
                (foreground
                    ? DecorationPosition.foreground
                    : DecorationPosition.background),
      ),
    ),
  );
  return box.decoration as BoxDecoration;
}
