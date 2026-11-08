import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lucent token 层：几何 / 颜色角色 / 排版。
void main() {
  group('BmTokens 常量', () {
    test('6 档圆角', () {
      expect(BmTokens.r4, 4);
      expect(BmTokens.r10, 10);
      expect(BmTokens.r14, 14);
      expect(BmTokens.r20, 20);
      expect(BmTokens.r28, 28);
      expect(BmTokens.rPill, 999);
      expect(BmTokens.r4All, const BorderRadius.all(Radius.circular(4)));
      expect(BmTokens.r10All, const BorderRadius.all(Radius.circular(10)));
      expect(BmTokens.r14All, const BorderRadius.all(Radius.circular(14)));
      expect(BmTokens.r20All, const BorderRadius.all(Radius.circular(20)));
      expect(BmTokens.r28All, const BorderRadius.all(Radius.circular(28)));
      expect(BmTokens.rPillAll, const BorderRadius.all(Radius.circular(999)));
    });

    test('7 档间距', () {
      expect(BmTokens.s1, 4);
      expect(BmTokens.s2, 8);
      expect(BmTokens.s3, 12);
      expect(BmTokens.s4, 16);
      expect(BmTokens.s5, 20);
      expect(BmTokens.s6, 24);
      expect(BmTokens.s8, 32);
    });

    test('行高 / 控件高 / 图标 / 触摸区', () {
      expect(BmTokens.rowCompact, 40);
      expect(BmTokens.row, 48);
      expect(BmTokens.rowTall, 56);
      expect(BmTokens.controlSm, 28);
      expect(BmTokens.controlMd, 34);
      expect(BmTokens.controlLg, 40);
      expect(BmTokens.iconInline, 14);
      expect(BmTokens.iconMenu, 16);
      expect(BmTokens.icon, 20);
      expect(BmTokens.iconLarge, 24);
      expect(BmTokens.touchDesktop, 40);
      expect(BmTokens.touchScreen, 44);
      expect(
        BmTokens.pagePadding,
        const EdgeInsets.symmetric(horizontal: BmTokens.s4),
      );
      expect(
        BmTokens.rowPadding,
        const EdgeInsets.symmetric(
          horizontal: BmTokens.s4,
          vertical: BmTokens.s2,
        ),
      );
    });

    test('Chrome / Stage 材质：描边 / 模糊 / 底栏 / 侧栏行', () {
      expect(BmTokens.hairlineWidth, 0.5);
      expect(BmTokens.chromeBlurSigma, 24);
      expect(BmTokens.stageCoverBlurSigma, 64);
      expect(BmTokens.navBarHeight, 56);
      expect(BmTokens.navRowHeight, 40);
      expect(BmTokens.navIndicatorWidth, 3);
    });

    test('扩展是单例：copyWith / lerp 返回自身', () {
      const tokens = BmTokens.standard;
      expect(tokens.copyWith(), same(tokens));
      expect(tokens.lerp(const BmTokens(), 0.5), same(tokens));
    });
  });

  group('BmAlpha 固定透明度', () {
    test('状态层 / 浮层 / Stage / 阴影', () {
      expect(BmAlpha.hover, 0.06);
      expect(BmAlpha.pressed, 0.10);
      expect(BmAlpha.selected, 0.12);
      expect(BmAlpha.border, 0.24);
      expect(BmAlpha.chrome, 0.72);
      expect(BmAlpha.chromeOpaque, 0.96);
      expect(BmAlpha.floating, 0.96);
      expect(BmAlpha.textTertiary, 0.60);
      expect(BmAlpha.disabled, 0.38);
      expect(BmAlpha.stageTextSecondary, 0.72);
      expect(BmAlpha.stageFill, 0.12);
      expect(BmAlpha.stageBorder, 0.20);
      expect(BmAlpha.stageCover, 0.70);
      expect(BmAlpha.shadow, 0.12);
      expect(BmAlpha.shadowStrong, 0.20);
      expect(BmAlpha.scrim, 0.32);
      expect(BmAlpha.dim, 0.15);
    });
  });

  group('BmColors.resolve', () {
    for (final descriptor in ThemeRegistry.all) {
      for (final brightness in Brightness.values) {
        final suffix = brightness == Brightness.light ? 'light' : 'dark';
        final theme = brightness == Brightness.light
            ? descriptor.light()
            : descriptor.dark();

        test('${descriptor.id} · $suffix：角色齐全且来源正确', () {
          final palette = theme.extension<AppPalette>();
          expect(palette, isNotNull);
          final scheme = theme.colorScheme;
          final colors = BmColors.resolve(scheme, palette!);

          // 30 个角色都拿到了有效色值（分量在 0..1，没有 NaN）。
          final roles = <String, Color>{
            'bg': colors.bg,
            'surface': colors.surface,
            'surfaceRaised': colors.surfaceRaised,
            'surfaceSunken': colors.surfaceSunken,
            'chrome': colors.chrome,
            'chromeOpaque': colors.chromeOpaque,
            'floating': colors.floating,
            'textPrimary': colors.textPrimary,
            'textSecondary': colors.textSecondary,
            'textTertiary': colors.textTertiary,
            'accent': colors.accent,
            'onAccent': colors.onAccent,
            'accentSoft': colors.accentSoft,
            'accentBorder': colors.accentBorder,
            'hairline': colors.hairline,
            'stateHover': colors.stateHover,
            'statePressed': colors.statePressed,
            'stateSelected': colors.stateSelected,
            'danger': colors.danger,
            'onDanger': colors.onDanger,
            'warning': colors.warning,
            'success': colors.success,
            'stageText': colors.stageText,
            'stageTextSecondary': colors.stageTextSecondary,
            'stageControlFill': colors.stageControlFill,
            'stageBorder': colors.stageBorder,
            'shadow': colors.shadow,
            'shadowStrong': colors.shadowStrong,
            'scrim': colors.scrim,
            'dim': colors.dim,
          };
          expect(roles.length, 30);
          for (final entry in roles.entries) {
            expect(
              entry.value.a,
              inInclusiveRange(0.0, 1.0),
              reason: '${entry.key}.a',
            );
            expect(
              entry.value.r,
              inInclusiveRange(0.0, 1.0),
              reason: '${entry.key}.r',
            );
            expect(
              entry.value.g,
              inInclusiveRange(0.0, 1.0),
              reason: '${entry.key}.g',
            );
            expect(
              entry.value.b,
              inInclusiveRange(0.0, 1.0),
              reason: '${entry.key}.b',
            );
          }

          // 不透明角色直接来自 ColorScheme / AppPalette。
          expect(colors.bg, scheme.surface);
          expect(colors.surface, scheme.surface);
          expect(colors.surfaceRaised, palette.panelSurface);
          expect(colors.surfaceSunken, palette.searchField);
          expect(colors.textPrimary, scheme.onSurface);
          expect(colors.textSecondary, scheme.onSurfaceVariant);
          expect(colors.accent, scheme.primary);
          expect(colors.hairline, scheme.outlineVariant);
          expect(colors.onAccent, scheme.onPrimary);
          expect(colors.danger, scheme.error);
          expect(colors.onDanger, scheme.onError);
          expect(colors.warning, palette.warning);
          expect(colors.success, palette.success);
          expect(colors.stageText, Colors.white);

          // 半透明角色：底色保留、alpha 只用固定值。
          expectRgb(colors.chrome, scheme.surface, 'chrome');
          expectAlpha(colors.chrome, BmAlpha.chrome, 'chrome');

          expectRgb(colors.chromeOpaque, scheme.surface, 'chromeOpaque');
          expectAlpha(
            colors.chromeOpaque,
            BmAlpha.chromeOpaque,
            'chromeOpaque',
          );

          expectRgb(colors.floating, scheme.surfaceContainerHigh, 'floating');
          expectAlpha(colors.floating, BmAlpha.floating, 'floating');

          expectRgb(
            colors.textTertiary,
            scheme.onSurfaceVariant,
            'textTertiary',
          );
          expectAlpha(
            colors.textTertiary,
            BmAlpha.textTertiary,
            'textTertiary',
          );

          expectRgb(colors.accentSoft, scheme.primary, 'accentSoft');
          expectAlpha(colors.accentSoft, BmAlpha.selected, 'accentSoft');

          expectRgb(colors.accentBorder, scheme.primary, 'accentBorder');
          expectAlpha(colors.accentBorder, BmAlpha.border, 'accentBorder');

          expectRgb(colors.stateHover, scheme.onSurface, 'stateHover');
          expectAlpha(colors.stateHover, BmAlpha.hover, 'stateHover');

          expectRgb(colors.statePressed, scheme.onSurface, 'statePressed');
          expectAlpha(colors.statePressed, BmAlpha.pressed, 'statePressed');

          expectRgb(colors.stateSelected, scheme.primary, 'stateSelected');
          expectAlpha(colors.stateSelected, BmAlpha.selected, 'stateSelected');

          expectRgb(
            colors.stageTextSecondary,
            Colors.white,
            'stageTextSecondary',
          );
          expectAlpha(
            colors.stageTextSecondary,
            BmAlpha.stageTextSecondary,
            'stageTextSecondary',
          );

          expectRgb(colors.stageControlFill, Colors.white, 'stageControlFill');
          expectAlpha(
            colors.stageControlFill,
            BmAlpha.stageFill,
            'stageControlFill',
          );

          expectRgb(colors.stageBorder, Colors.white, 'stageBorder');
          expectAlpha(colors.stageBorder, BmAlpha.stageBorder, 'stageBorder');

          expectRgb(colors.shadow, Colors.black, 'shadow');
          expectAlpha(colors.shadow, BmAlpha.shadow, 'shadow');

          expectRgb(colors.shadowStrong, Colors.black, 'shadowStrong');
          expectAlpha(
            colors.shadowStrong,
            BmAlpha.shadowStrong,
            'shadowStrong',
          );

          expectRgb(colors.scrim, Colors.black, 'scrim');
          expectAlpha(colors.scrim, BmAlpha.scrim, 'scrim');

          expectRgb(colors.dim, Colors.black, 'dim');
          expectAlpha(colors.dim, BmAlpha.dim, 'dim');
        });
      }
    }
  });

  testWidgets('未注入扩展时 context.bm / context.bmColors 回退不抛异常', (tester) async {
    late BmTokens tokens;
    late BmColors colors;
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light()),
        home: Builder(
          builder: (context) {
            tokens = context.bm;
            colors = context.bmColors;
            scheme = Theme.of(context).colorScheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(tokens, same(BmTokens.standard));
    // 回退路径按当前 ColorScheme + AppPaletteFallback.light 现算。
    expect(colors.accent, scheme.primary);
    expect(colors.hairline, scheme.outlineVariant);
    expect(colors.warning, isA<Color>());
    expect(colors.success, isA<Color>());
  });

  group('BmTypography 8 档', () {
    final cases = <(String, TextStyle, double, double, FontWeight)>[
      ('display', BmTypography.display(null), 28, 34, FontWeight.w700),
      ('title', BmTypography.title(null), 22, 28, FontWeight.w700),
      ('headline', BmTypography.headline(null), 17, 24, FontWeight.w600),
      ('body', BmTypography.body(null), 15, 22, FontWeight.w400),
      ('bodyStrong', BmTypography.bodyStrong(null), 15, 22, FontWeight.w600),
      ('label', BmTypography.label(null), 13, 18, FontWeight.w500),
      ('caption', BmTypography.caption(null), 12, 16, FontWeight.w400),
      ('micro', BmTypography.micro(null), 11, 14, FontWeight.w500),
    ];

    for (final (name, style, size, lineHeight, weight) in cases) {
      test('$name：字号 / 行高 / 字重 / 字体栈', () {
        expect(style.fontSize, size);
        expect(style.height, isNotNull);
        expect(style.height! * style.fontSize!, closeTo(lineHeight, 1e-9));
        expect(style.fontWeight, weight);
        expect(style.fontFamilyFallback, BmTypography.fontFallback);
        expect(style.color, isNull);
      });
    }

    test('numeric() 追加 tabularFigures 且保留既有 feature', () {
      final base = BmTypography.body(Colors.black);
      final numeric = BmTypography.numeric(base);
      expect(numeric.fontSize, base.fontSize);
      expect(numeric.fontWeight, base.fontWeight);
      expect(
        numeric.fontFeatures!.any((f) => f.feature == 'tnum'),
        isTrue,
        reason: 'tabularFigures 的 feature tag 是 tnum',
      );
      expect(
        numeric.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      final withExisting = base.copyWith(
        fontFeatures: const <FontFeature>[FontFeature.slashedZero()],
      );
      final numeric2 = BmTypography.numeric(withExisting);
      expect(numeric2.fontFeatures!.first, const FontFeature.slashedZero());
      expect(
        numeric2.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('TextTheme 15 个槽位全非空且字号来自 8 档', () {
      final scheme = ThemeRegistry.defaultTheme.light().colorScheme;
      final textTheme = BmTypography.theme(scheme);
      const expectedSizes = <String, double>{
        'displayLarge': 28,
        'displayMedium': 28,
        'displaySmall': 28,
        'headlineLarge': 22,
        'headlineMedium': 22,
        'headlineSmall': 17,
        'titleLarge': 17,
        'titleMedium': 15,
        'titleSmall': 13,
        'bodyLarge': 15,
        'bodyMedium': 15,
        'bodySmall': 12,
        'labelLarge': 13,
        'labelMedium': 12,
        'labelSmall': 11,
      };
      final actual = <String, TextStyle?>{
        'displayLarge': textTheme.displayLarge,
        'displayMedium': textTheme.displayMedium,
        'displaySmall': textTheme.displaySmall,
        'headlineLarge': textTheme.headlineLarge,
        'headlineMedium': textTheme.headlineMedium,
        'headlineSmall': textTheme.headlineSmall,
        'titleLarge': textTheme.titleLarge,
        'titleMedium': textTheme.titleMedium,
        'titleSmall': textTheme.titleSmall,
        'bodyLarge': textTheme.bodyLarge,
        'bodyMedium': textTheme.bodyMedium,
        'bodySmall': textTheme.bodySmall,
        'labelLarge': textTheme.labelLarge,
        'labelMedium': textTheme.labelMedium,
        'labelSmall': textTheme.labelSmall,
      };
      expect(actual.length, 15);
      for (final entry in expectedSizes.entries) {
        final style = actual[entry.key];
        expect(style, isNotNull, reason: entry.key);
        expect(style!.fontSize, entry.value, reason: entry.key);
        expect(
          <double>{28, 22, 17, 15, 13, 12, 11},
          contains(style.fontSize),
          reason: '${entry.key} 的字号必须来自 8 档',
        );
      }
      // 主文字 / 次文字分别取 onSurface / onSurfaceVariant。
      expect(textTheme.bodyLarge!.color, scheme.onSurface);
      expect(textTheme.bodySmall!.color, scheme.onSurfaceVariant);
      expect(textTheme.labelSmall!.color, scheme.onSurfaceVariant);
    });
  });

  group('AppPalette 语义色', () {
    for (final descriptor in ThemeRegistry.all) {
      test(descriptor.id, () {
        for (final brightness in Brightness.values) {
          final theme = brightness == Brightness.light
              ? descriptor.light()
              : descriptor.dark();
          final palette = theme.extension<AppPalette>();
          expect(palette, isNotNull, reason: '${descriptor.id} · $brightness');
          expect(palette!.warning, isA<Color>());
          expect(palette.success, isA<Color>());
          expect(palette.warning.a, 1.0);
          expect(palette.success.a, 1.0);
        }
      });
    }
  });
}

/// 半透明角色必须保留来源色的 RGB。
void expectRgb(Color actual, Color base, String reason) {
  expect(actual.r, closeTo(base.r, 1e-9), reason: '$reason.r');
  expect(actual.g, closeTo(base.g, 1e-9), reason: '$reason.g');
  expect(actual.b, closeTo(base.b, 1e-9), reason: '$reason.b');
}

/// 透明度断言：同时用 double 与 8bit 两种写法，兼容 Flutter 的 Color 表示。
void expectAlpha(Color color, double expected, String reason) {
  expect(color.a, closeTo(expected, 1e-6), reason: '$reason.a');
  expect(
    (color.a * 255).round(),
    (expected * 255).round(),
    reason: '$reason 的 8bit alpha',
  );
}
