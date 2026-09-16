import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// Nord 主题颜色常量 —— Arctic Ice Studio 的 Nord 调色板
/// (https://www.nordtheme.com/)。灵感来自极地冰雪与极光,色调冷静、低饱和,
/// 是非常受欢迎的 IDE/编辑器配色之一。
///
/// Light 走 nord6 雪暴白底 + nord10 深冻蓝 accent,Dark 走 nord0 极夜底 +
/// nord8 亮冻青 accent。
abstract class NordColors {
  // ===== Accent =====
  static const Color primaryLight = Color(0xFF5E81AC); // nord10 frost
  static const Color primaryDark = Color(0xFF88C0D0); // nord8 frost cyan

  // ===== Surface (Light) —— nord6 / nord5 / nord4 雪暴阶梯 =====
  static const Color surfaceLight = Color(0xFFECEFF4);
  static const Color surfaceContainerLight = Color(0xFFE5E9F0);
  static const Color surfaceContainerHighLight = Color(0xFFD8DEE9);

  // ===== Surface (Dark) —— nord0 / nord1 / nord2 极夜阶梯 =====
  static const Color surfaceDark = Color(0xFF2E3440);
  static const Color surfaceContainerDark = Color(0xFF3B4252);
  static const Color surfaceContainerHighDark = Color(0xFF434C5E);

  // ===== Text (Light) =====
  static const Color onSurfaceLight = Color(0xFF2E3440); // nord0
  static const Color onSurfaceVariantLight = Color(0xFF4C566A); // nord3

  // ===== Text (Dark) =====
  static const Color onSurfaceDark = Color(0xFFECEFF4); // nord6
  static const Color onSurfaceVariantDark = Color(0xFFD8DEE9); // nord4

  // ===== Outline —— 冷色低透明度 =====
  static const Color outlineLight = Color(0x1F2E3440);
  static const Color outlineVariantLight = Color(0x0F2E3440);
  static const Color outlineDark = Color(0x1FECEFF4);
  static const Color outlineVariantDark = Color(0x0FECEFF4);

  // ===== Semantic =====
  static const Color errorLight = Color(0xFFBF616A); // nord11
  static const Color errorDark = Color(0xFFBF616A);
  static const Color successLight = Color(0xFFA3BE8C); // nord14
  static const Color successDark = Color(0xFFA3BE8C);
}

AppPalette _nordPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: NordColors.surfaceContainerLight,
      bottomBar: NordColors.surfaceContainerLight,
      panelSurface: NordColors.surfaceContainerLight,
      selectedItem: NordColors.surfaceContainerHighLight,
      searchField: NordColors.surfaceContainerLight,
      playBar: NordColors.surfaceContainerLight,
      seekBarActive: NordColors.onSurfaceLight,
      volumeBarActive: NordColors.onSurfaceLight,
      surfaceOverlay: Color(0xCCECEFF4),
      surfaceHover: NordColors.surfaceContainerHighLight,
      surfacePressed: NordColors.surfaceContainerHighLight,
    );
  }
  return const AppPalette(
    sidebarSurface: NordColors.surfaceContainerDark,
    bottomBar: NordColors.surfaceContainerDark,
    panelSurface: NordColors.surfaceContainerDark,
    selectedItem: NordColors.surfaceContainerHighDark,
    searchField: NordColors.surfaceContainerDark,
    playBar: NordColors.surfaceContainerDark,
    seekBarActive: NordColors.onSurfaceVariantDark,
    volumeBarActive: NordColors.onSurfaceVariantDark,
    surfaceOverlay: Color(0xBF2E3440),
    surfaceHover: NordColors.surfaceContainerHighDark,
    surfacePressed: NordColors.surfaceContainerHighDark,
  );
}

ColorScheme _nordColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: NordColors.primaryLight,
      onPrimary: Colors.white,
      secondary: NordColors.primaryLight,
      onSecondary: Colors.white,
      tertiary: NordColors.primaryDark,
      onTertiary: Colors.black,
      error: NordColors.errorLight,
      onError: Colors.white,
      surface: NordColors.surfaceLight,
      onSurface: NordColors.onSurfaceLight,
      onSurfaceVariant: NordColors.onSurfaceVariantLight,
      surfaceContainerLowest: NordColors.surfaceLight,
      surfaceContainerLow: NordColors.surfaceLight,
      surfaceContainer: NordColors.surfaceContainerLight,
      surfaceContainerHigh: NordColors.surfaceContainerHighLight,
      surfaceContainerHighest: NordColors.surfaceContainerHighLight,
      outline: NordColors.outlineLight,
      outlineVariant: NordColors.outlineVariantLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: NordColors.onSurfaceLight,
      onInverseSurface: NordColors.surfaceLight,
      inversePrimary: NordColors.primaryDark,
      surfaceTint: NordColors.primaryLight,
    );
  }
  return ColorScheme(
    brightness: Brightness.dark,
    primary: NordColors.primaryDark,
    onPrimary: Colors.black,
    secondary: NordColors.primaryDark,
    onSecondary: Colors.black,
    tertiary: NordColors.primaryLight,
    onTertiary: Colors.black,
    error: NordColors.errorDark,
    onError: Colors.black,
    surface: NordColors.surfaceDark,
    onSurface: NordColors.onSurfaceDark,
    onSurfaceVariant: NordColors.onSurfaceVariantDark,
    surfaceContainerLowest: NordColors.surfaceDark,
    surfaceContainerLow: NordColors.surfaceDark,
    surfaceContainer: NordColors.surfaceContainerDark,
    surfaceContainerHigh: NordColors.surfaceContainerHighDark,
    surfaceContainerHighest: NordColors.surfaceContainerHighDark,
    outline: NordColors.outlineDark,
    outlineVariant: NordColors.outlineVariantDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: NordColors.onSurfaceDark,
    onInverseSurface: NordColors.surfaceDark,
    inversePrimary: NordColors.primaryLight,
    surfaceTint: NordColors.primaryDark,
  );
}

ThemeData _buildNord(Brightness brightness) {
  final scheme = _nordColorScheme(brightness);
  final palette = _nordPalette(brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [palette],
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      elevation: 0,
      color: scheme.surfaceContainer,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        borderSide: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        borderSide: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        borderSide: BorderSide(color: scheme.primary, width: 0.5),
      ),
      filled: true,
      fillColor: scheme.surfaceContainer,
    ),
    scaffoldBackgroundColor: scheme.surface,
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHigh,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outline,
      thickness: 0.5,
      space: 0.5,
    ),
    dividerColor: scheme.outline,
  );
}

/// Nord Theme factory for Flutter ThemeData
abstract class NordTheme {
  static ThemeData lightTheme() => _buildNord(Brightness.light);
  static ThemeData darkTheme() => _buildNord(Brightness.dark);
}
