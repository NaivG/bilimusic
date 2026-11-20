import 'package:flutter/material.dart';

import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/ui/theme/bm_component_themes.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 把「主题色值」组装成完整 [ThemeData] 的唯一入口。
///
/// 6 套主题只提供 [ColorScheme] + [AppPalette]；几何、字号、组件状态层、
/// 默认动效全部走 Lucent token，新增主题不需要再碰组件样式。
abstract class BmTheme {
  static ThemeData build({
    required ColorScheme scheme,
    required AppPalette palette,
  }) {
    final colors = BmColors.resolve(scheme, palette);
    final type = BmTypographySet.resolve(scheme);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[palette, const BmTokens(), colors],
      textTheme: BmTypography.theme(scheme),
      fontFamilyFallback: BmTypography.fontFallback,
      iconTheme: BmComponentThemes.icon(colors),
      appBarTheme: BmComponentThemes.appBar(colors, type),
      dialogTheme: BmComponentThemes.dialog(colors, type),
      bottomSheetTheme: BmComponentThemes.sheet(colors),
      cardTheme: BmComponentThemes.card(colors),
      filledButtonTheme: BmComponentThemes.filledButton(colors, type),
      textButtonTheme: BmComponentThemes.textButton(colors, type),
      outlinedButtonTheme: BmComponentThemes.outlinedButton(colors, type),
      elevatedButtonTheme: BmComponentThemes.elevatedButton(colors, type),
      chipTheme: BmComponentThemes.chip(colors, type),
      tooltipTheme: BmComponentThemes.tooltip(colors, type),
      navigationBarTheme: BmComponentThemes.navBar(colors, type),
      inputDecorationTheme: BmComponentThemes.input(colors, type),
      dividerTheme: BmComponentThemes.divider(colors),
      sliderTheme: BmComponentThemes.slider(colors),
      listTileTheme: BmComponentThemes.listTile(type),
      snackBarTheme: BmComponentThemes.snackBar(scheme, colors),
      textSelectionTheme: BmComponentThemes.textSelection(colors),
      progressIndicatorTheme: BmComponentThemes.progress(colors),
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: colors.hairline,
      hoverColor: colors.stateHover,
      highlightColor: colors.statePressed,
      focusColor: colors.stateHover,
      splashColor: Colors.transparent,
      // 状态层由组件自己画（BmPressable / BmButton），不再叠 Material 水波
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}
