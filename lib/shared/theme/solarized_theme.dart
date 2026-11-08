import 'package:flutter/material.dart';

import '../ui/theme/bm_theme.dart';
import 'app_palette.dart';

/// Solarized 主题颜色常量 —— Ethan Schoonover 的经典 Solarized 调色板
/// (https://ethanschoonover.com/solarized/)。被广泛用于终端、IDE 与编辑器,
/// 强调柔和对比与长时间阅读的舒适度。
///
/// Light 走 base3 暖米纸底 + 深蓝 accent,Dark 走 base03 深青蓝底 + 亮青 accent。
abstract class SolarizedColors {
  // ===== Accent =====
  static const Color primaryLight = Color(0xFF268BD2); // Solarized blue
  static const Color primaryDark = Color(0xFF2AA198); // Solarized cyan

  // ===== Surface (Light) —— Solarized base3 / base2 米纸阶梯 =====
  static const Color surfaceLight = Color(0xFFFDF6E3);
  static const Color surfaceContainerLight = Color(0xFFEEE8D5);
  static const Color surfaceContainerHighLight = Color(0xFFE5DFC6);

  // ===== Surface (Dark) —— Solarized base03 / base02 深青阶梯 =====
  static const Color surfaceDark = Color(0xFF002B36);
  static const Color surfaceContainerDark = Color(0xFF073642);
  static const Color surfaceContainerHighDark = Color(0xFF0A4856);

  // ===== Text (Light) =====
  static const Color onSurfaceLight = Color(0xFF073642); // base02
  static const Color onSurfaceVariantLight = Color(0xFF586E75); // base01

  // ===== Text (Dark) =====
  static const Color onSurfaceDark = Color(0xFF93A1A1); // base1
  static const Color onSurfaceVariantDark = Color(0xFF839496); // base0

  // ===== Outline —— 低透明度的 base01/base0 =====
  static const Color outlineLight = Color(0x1F073642);
  static const Color outlineVariantLight = Color(0x0F073642);
  static const Color outlineDark = Color(0x1F93A1A1);
  static const Color outlineVariantDark = Color(0x0F93A1A1);

  // ===== Semantic =====
  static const Color errorLight = Color(0xFFDC322F);
  static const Color errorDark = Color(0xFFF2777A);
  static const Color warningLight = Color(0xFFB58900); // Solarized yellow
  static const Color warningDark = Color(0xFFB58900);
  static const Color successLight = Color(0xFF859900);
  static const Color successDark = Color(0xFF859900);
}

AppPalette _solarizedPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: SolarizedColors.surfaceContainerLight,
      bottomBar: SolarizedColors.surfaceContainerLight,
      panelSurface: SolarizedColors.surfaceContainerLight,
      selectedItem: SolarizedColors.surfaceContainerHighLight,
      searchField: SolarizedColors.surfaceContainerLight,
      playBar: SolarizedColors.surfaceContainerLight,
      seekBarActive: SolarizedColors.onSurfaceLight,
      volumeBarActive: SolarizedColors.onSurfaceLight,
      warning: SolarizedColors.warningLight,
      success: SolarizedColors.successLight,
      surfaceOverlay: Color(0xCCFDF6E3),
      surfaceHover: SolarizedColors.surfaceContainerHighLight,
      surfacePressed: SolarizedColors.surfaceContainerHighLight,
    );
  }
  return const AppPalette(
    sidebarSurface: SolarizedColors.surfaceContainerDark,
    bottomBar: SolarizedColors.surfaceContainerDark,
    panelSurface: SolarizedColors.surfaceContainerDark,
    selectedItem: SolarizedColors.surfaceContainerHighDark,
    searchField: SolarizedColors.surfaceContainerDark,
    playBar: SolarizedColors.surfaceContainerDark,
    seekBarActive: SolarizedColors.onSurfaceVariantDark,
    volumeBarActive: SolarizedColors.onSurfaceVariantDark,
    warning: SolarizedColors.warningDark,
    success: SolarizedColors.successDark,
    surfaceOverlay: Color(0xBF002B36),
    surfaceHover: SolarizedColors.surfaceContainerHighDark,
    surfacePressed: SolarizedColors.surfaceContainerHighDark,
  );
}

ColorScheme _solarizedColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: SolarizedColors.primaryLight,
      onPrimary: Colors.white,
      secondary: SolarizedColors.primaryLight,
      onSecondary: Colors.white,
      tertiary: SolarizedColors.primaryDark,
      onTertiary: Colors.white,
      error: SolarizedColors.errorLight,
      onError: Colors.white,
      surface: SolarizedColors.surfaceLight,
      onSurface: SolarizedColors.onSurfaceLight,
      onSurfaceVariant: SolarizedColors.onSurfaceVariantLight,
      surfaceContainerLowest: SolarizedColors.surfaceLight,
      surfaceContainerLow: SolarizedColors.surfaceLight,
      surfaceContainer: SolarizedColors.surfaceContainerLight,
      surfaceContainerHigh: SolarizedColors.surfaceContainerHighLight,
      surfaceContainerHighest: SolarizedColors.surfaceContainerHighLight,
      outline: SolarizedColors.outlineLight,
      outlineVariant: SolarizedColors.outlineVariantLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: SolarizedColors.onSurfaceLight,
      onInverseSurface: SolarizedColors.surfaceLight,
      inversePrimary: SolarizedColors.primaryDark,
      surfaceTint: SolarizedColors.primaryLight,
    );
  }
  return ColorScheme(
    brightness: Brightness.dark,
    primary: SolarizedColors.primaryDark,
    onPrimary: Colors.black,
    secondary: SolarizedColors.primaryDark,
    onSecondary: Colors.black,
    tertiary: SolarizedColors.primaryLight,
    onTertiary: Colors.black,
    error: SolarizedColors.errorDark,
    onError: Colors.black,
    surface: SolarizedColors.surfaceDark,
    onSurface: SolarizedColors.onSurfaceDark,
    onSurfaceVariant: SolarizedColors.onSurfaceVariantDark,
    surfaceContainerLowest: SolarizedColors.surfaceDark,
    surfaceContainerLow: SolarizedColors.surfaceDark,
    surfaceContainer: SolarizedColors.surfaceContainerDark,
    surfaceContainerHigh: SolarizedColors.surfaceContainerHighDark,
    surfaceContainerHighest: SolarizedColors.surfaceContainerHighDark,
    outline: SolarizedColors.outlineDark,
    outlineVariant: SolarizedColors.outlineVariantDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: SolarizedColors.onSurfaceDark,
    onInverseSurface: SolarizedColors.surfaceDark,
    inversePrimary: SolarizedColors.primaryLight,
    surfaceTint: SolarizedColors.primaryDark,
  );
}

ThemeData _buildSolarized(Brightness brightness) {
  return BmTheme.build(
    scheme: _solarizedColorScheme(brightness),
    palette: _solarizedPalette(brightness),
  );
}

/// Solarized Theme factory for Flutter ThemeData
abstract class SolarizedTheme {
  static ThemeData lightTheme() => _buildSolarized(Brightness.light);
  static ThemeData darkTheme() => _buildSolarized(Brightness.dark);
}
