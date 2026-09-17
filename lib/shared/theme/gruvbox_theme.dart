import 'package:flutter/material.dart';

import 'app_component_themes.dart';
import 'app_palette.dart';
import 'app_tokens.dart';

/// Gruvbox 主题颜色常量 —— Pavel Pertsev 的经典 retro groove 调色板
/// (https://github.com/gruvbox-community/gruvbox)。灵感来自 80 年代终端与
/// 复古印刷品,色调暖调、对比柔和,以长时间阅读的舒适度著称。
///
/// Light 走 bg0 米色底 + 暖橙 accent,Dark 走 bg0 深棕底 + 亮橙 accent。
abstract class GruvboxColors {
  // ===== Accent =====
  static const Color primaryLight = Color(0xFFAF3A03); // light bright orange
  static const Color primaryDark = Color(0xFFFE8019); // dark bright orange

  // ===== Surface (Light) —— gruvbox bg0/bg1/bg2 米色阶梯 =====
  static const Color surfaceLight = Color(0xFFF9F5D7);
  static const Color surfaceContainerLight = Color(0xFFEBDBB2);
  static const Color surfaceContainerHighLight = Color(0xFFD5C4A1);

  // ===== Surface (Dark) —— gruvbox bg0/bg1/bg2 深棕阶梯 =====
  static const Color surfaceDark = Color(0xFF282828);
  static const Color surfaceContainerDark = Color(0xFF3C3836);
  static const Color surfaceContainerHighDark = Color(0xFF504945);

  // ===== Text (Light) =====
  static const Color onSurfaceLight = Color(0xFF3C3836); // fg1 / bg1_dark
  static const Color onSurfaceVariantLight = Color(
    0xFF7C6F64,
  ); // fg4 / bg4_dark

  // ===== Text (Dark) =====
  static const Color onSurfaceDark = Color(0xFFEBDBB2); // fg1 / bg1_light
  static const Color onSurfaceVariantDark = Color(
    0xFFA89984,
  ); // fg4 / bg4_light

  // ===== Outline —— 暖色低透明度 =====
  static const Color outlineLight = Color(0x1F3C3836);
  static const Color outlineVariantLight = Color(0x0F3C3836);
  static const Color outlineDark = Color(0x1FEBDBB2);
  static const Color outlineVariantDark = Color(0x0FEBDBB2);

  // ===== Semantic =====
  static const Color errorLight = Color(0xFF9D0006);
  static const Color errorDark = Color(0xFFFB4934);
  static const Color successLight = Color(0xFF79740E);
  static const Color successDark = Color(0xFFB8BB26);
}

AppPalette _gruvboxPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: GruvboxColors.surfaceContainerLight,
      bottomBar: GruvboxColors.surfaceContainerLight,
      panelSurface: GruvboxColors.surfaceContainerLight,
      selectedItem: GruvboxColors.surfaceContainerHighLight,
      searchField: GruvboxColors.surfaceContainerLight,
      playBar: GruvboxColors.surfaceContainerLight,
      seekBarActive: GruvboxColors.onSurfaceLight,
      volumeBarActive: GruvboxColors.onSurfaceLight,
      surfaceOverlay: Color(0xCCF9F5D7),
      surfaceHover: GruvboxColors.surfaceContainerHighLight,
      surfacePressed: GruvboxColors.surfaceContainerHighLight,
    );
  }
  return const AppPalette(
    sidebarSurface: GruvboxColors.surfaceContainerDark,
    bottomBar: GruvboxColors.surfaceContainerDark,
    panelSurface: GruvboxColors.surfaceContainerDark,
    selectedItem: GruvboxColors.surfaceContainerHighDark,
    searchField: GruvboxColors.surfaceContainerDark,
    playBar: GruvboxColors.surfaceContainerDark,
    seekBarActive: GruvboxColors.onSurfaceVariantDark,
    volumeBarActive: GruvboxColors.onSurfaceVariantDark,
    surfaceOverlay: Color(0xBF282828),
    surfaceHover: GruvboxColors.surfaceContainerHighDark,
    surfacePressed: GruvboxColors.surfaceContainerHighDark,
  );
}

ColorScheme _gruvboxColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: GruvboxColors.primaryLight,
      onPrimary: Colors.white,
      secondary: GruvboxColors.primaryLight,
      onSecondary: Colors.white,
      tertiary: Color(0xFFB57614), // light bright yellow
      onTertiary: Colors.white,
      error: GruvboxColors.errorLight,
      onError: Colors.white,
      surface: GruvboxColors.surfaceLight,
      onSurface: GruvboxColors.onSurfaceLight,
      onSurfaceVariant: GruvboxColors.onSurfaceVariantLight,
      surfaceContainerLowest: GruvboxColors.surfaceLight,
      surfaceContainerLow: GruvboxColors.surfaceLight,
      surfaceContainer: GruvboxColors.surfaceContainerLight,
      surfaceContainerHigh: GruvboxColors.surfaceContainerHighLight,
      surfaceContainerHighest: GruvboxColors.surfaceContainerHighLight,
      outline: GruvboxColors.outlineLight,
      outlineVariant: GruvboxColors.outlineVariantLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: GruvboxColors.onSurfaceLight,
      onInverseSurface: GruvboxColors.surfaceLight,
      inversePrimary: GruvboxColors.primaryDark,
      surfaceTint: GruvboxColors.primaryLight,
    );
  }
  return ColorScheme(
    brightness: Brightness.dark,
    primary: GruvboxColors.primaryDark,
    onPrimary: Colors.black,
    secondary: GruvboxColors.primaryDark,
    onSecondary: Colors.black,
    tertiary: Color(0xFFFABD2F), // dark bright yellow
    onTertiary: Colors.black,
    error: GruvboxColors.errorDark,
    onError: Colors.black,
    surface: GruvboxColors.surfaceDark,
    onSurface: GruvboxColors.onSurfaceDark,
    onSurfaceVariant: GruvboxColors.onSurfaceVariantDark,
    surfaceContainerLowest: GruvboxColors.surfaceDark,
    surfaceContainerLow: GruvboxColors.surfaceDark,
    surfaceContainer: GruvboxColors.surfaceContainerDark,
    surfaceContainerHigh: GruvboxColors.surfaceContainerHighDark,
    surfaceContainerHighest: GruvboxColors.surfaceContainerHighDark,
    outline: GruvboxColors.outlineDark,
    outlineVariant: GruvboxColors.outlineVariantDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: GruvboxColors.onSurfaceDark,
    onInverseSurface: GruvboxColors.surfaceDark,
    inversePrimary: GruvboxColors.primaryLight,
    surfaceTint: GruvboxColors.primaryDark,
  );
}

ThemeData _buildGruvbox(Brightness brightness) {
  final scheme = _gruvboxColorScheme(brightness);
  final palette = _gruvboxPalette(brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [palette],
    snackBarTheme: AppComponentThemes.snackBar(scheme),
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

/// Gruvbox Theme factory for Flutter ThemeData
abstract class GruvboxTheme {
  static ThemeData lightTheme() => _buildGruvbox(Brightness.light);
  static ThemeData darkTheme() => _buildGruvbox(Brightness.dark);
}
