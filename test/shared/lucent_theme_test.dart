import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 6 主题 × 明暗 = 12 套 ThemeData 的组装结果。
void main() {
  test('注册表：6 个主题、id 唯一', () {
    expect(ThemeRegistry.all.length, 6);
    expect(ThemeRegistry.all.map((t) => t.id).toSet().length, 6);
    expect(ThemeRegistry.defaultTheme.id, 'lucent');
  });

  for (final descriptor in ThemeRegistry.all) {
    for (final brightness in Brightness.values) {
      final suffix = brightness == Brightness.light ? 'light' : 'dark';
      final theme = brightness == Brightness.light
          ? descriptor.light()
          : descriptor.dark();
      final scheme = theme.colorScheme;
      final palette = theme.extension<AppPalette>();
      final colors = theme.extension<BmColors>();

      group('${descriptor.id} · $suffix', () {
        test('extensions 含 AppPalette / BmTokens / BmColors', () {
          expect(theme.extensions, isNotNull);
          expect(theme.extensions.length, 3);
          expect(theme.extension<AppPalette>(), isNotNull);
          expect(theme.extension<BmTokens>(), isNotNull);
          expect(theme.extension<BmColors>(), isNotNull);
          expect(palette, isNotNull);
          expect(colors, isNotNull);
          // 扩展里的 BmColors 必须和 ColorScheme + AppPalette 一致。
          final resolved = BmColors.resolve(scheme, palette!);
          expect(colors!.accent, resolved.accent);
          expect(colors.hairline, resolved.hairline);
          expect(colors.stateHover, resolved.stateHover);
        });

        test('基础色 / 亮度 / M3 开关', () {
          expect(theme.useMaterial3, isTrue);
          expect(theme.brightness, brightness);
          expect(scheme.brightness, brightness);
          expect(theme.scaffoldBackgroundColor, scheme.surface);
          expect(theme.dividerColor, colors!.hairline);
          expect(theme.hoverColor, colors.stateHover);
          expect(theme.highlightColor, colors.statePressed);
          expect(theme.focusColor, colors.stateHover);
          expect(theme.splashColor, Colors.transparent);
          expect(theme.splashFactory, NoSplash.splashFactory);
          expect(theme.visualDensity, VisualDensity.standard);
        });

        test('textTheme 三档字号（15 / 13 / 17）', () {
          expect(theme.textTheme.bodyLarge, isNotNull);
          expect(theme.textTheme.bodyLarge!.fontSize, 15);
          expect(theme.textTheme.labelLarge, isNotNull);
          expect(theme.textTheme.labelLarge!.fontSize, 13);
          expect(theme.textTheme.headlineSmall, isNotNull);
          expect(theme.textTheme.headlineSmall!.fontSize, 17);
        });

        test('对话框 / Sheet / 按钮圆角', () {
          final dialogShape = theme.dialogTheme.shape;
          expect(dialogShape, isA<RoundedRectangleBorder>());
          expect(
            (dialogShape! as RoundedRectangleBorder).borderRadius,
            BmTokens.r20All,
          );
          expect(theme.dialogTheme.backgroundColor, colors!.floating);
          expect(theme.dialogTheme.barrierColor, colors.scrim);

          final sheetShape = theme.bottomSheetTheme.shape;
          expect(sheetShape, isA<RoundedRectangleBorder>());
          expect(
            (sheetShape! as RoundedRectangleBorder).borderRadius,
            const BorderRadius.vertical(top: Radius.circular(BmTokens.r20)),
          );
          expect(theme.bottomSheetTheme.backgroundColor, colors.floating);
          expect(theme.bottomSheetTheme.modalBackgroundColor, colors.floating);
          expect(theme.bottomSheetTheme.modalBarrierColor, colors.scrim);

          expect(buttonRadius(theme.filledButtonTheme.style), BmTokens.r10All);
          expect(buttonRadius(theme.textButtonTheme.style), BmTokens.r10All);
          expect(
            buttonRadius(theme.outlinedButtonTheme.style),
            BmTokens.r10All,
          );
          expect(
            buttonRadius(theme.elevatedButtonTheme.style),
            BmTokens.r10All,
          );
        });

        test('input / divider / card / snackBar 主题', () {
          expect(
            theme.inputDecorationTheme.fillColor,
            palette!.searchField,
            reason: '输入框底色必须等于 AppPalette.searchField',
          );
          expect(theme.inputDecorationTheme.filled, isTrue);

          expect(theme.dividerTheme.thickness, 0.5);
          expect(theme.dividerTheme.space, 0.5);
          expect(theme.dividerTheme.color, scheme.outlineVariant);
          expect(theme.dividerTheme.color, colors!.hairline);

          expect(theme.cardTheme.color, palette.panelSurface);

          // 既有 test/shell/snack_bar_boundary_test.dart 依赖这三项。
          expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
          expect(
            theme.snackBarTheme.backgroundColor,
            scheme.surfaceContainerHigh,
          );
          expect(theme.snackBarTheme.contentTextStyle, isNotNull);
          expect(theme.snackBarTheme.contentTextStyle!.color, scheme.onSurface);
          expect(theme.snackBarTheme.elevation, 0);
          final snackShape = theme.snackBarTheme.shape;
          expect(snackShape, isA<RoundedRectangleBorder>());
          expect(
            (snackShape! as RoundedRectangleBorder).borderRadius,
            BorderRadius.circular(AppTokens.radiusLg),
          );
        });
      });
    }
  }
}

/// 取按钮主题里的圆角；返回 null 表示没有显式设置。
BorderRadiusGeometry? buttonRadius(ButtonStyle? style) {
  final shape = style?.shape?.resolve(const <WidgetState>{});
  return shape is RoundedRectangleBorder ? shape.borderRadius : null;
}
