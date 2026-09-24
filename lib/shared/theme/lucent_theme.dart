import 'package:flutter/material.dart';

import 'app_component_themes.dart';
import 'app_palette.dart';
import 'app_tokens.dart';

/// Lucent 主题颜色常量 —— iOS 风格,暖灰底 + 湖水青蓝 accent。
/// 跨主题共享的颜色请通过 [AppPalette] 读取。
///
/// 孩子们雷霆大紫色真的是太丑了，我能说什么呢。
abstract class LucentColors {
  // ===== Accent —— 湖水青蓝 =====
  static const Color primaryLight = Color(0xFF30B0C7); // iOS Teal 湖水青
  static const Color primaryDark = Color(0xFF4DD0E1); // 亮湖水青
  static const Color secondaryLight = Color(0xFF0A84FF); // iOS Blue 青蓝
  static const Color secondaryDark = Color(0xFF64D2FF); // 亮天蓝

  // ===== Surface (Light) —— 暖灰阶梯 =====
  static const Color surfaceLight = Color(0xFFFAF9F7);
  static const Color surfaceContainerLight = Color(0xFFF5F4F2);
  static const Color surfaceContainerHighLight = Color(0xFFECEAE7);
  static const Color surfaceRaisedLight = Color(0xFFFFFFFF);

  // ===== Surface (Dark) =====
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color surfaceContainerDark = Color(0xFF2C2C2E);
  static const Color surfaceContainerHighDark = Color(0xFF3A3A3C);
  static const Color surfaceRaisedDark = Color(0xFF2C2C2E);

  // ===== Text (Light) =====
  static const Color onSurfaceLight = Color(0xFF1A1A1A);
  static const Color onSurfaceVariantLight = Color(0xFF6E6E73);

  // ===== Text (Dark) =====
  static const Color onSurfaceDark = Color(0xFFF5F5F7);
  static const Color onSurfaceVariantDark = Color(0xFF98989D);

  // ===== Outline —— 中性低透明度 =====
  static const Color outlineLight = Color(0x0F000000);
  static const Color outlineVariantLight = Color(0x08000000);
  static const Color outlineDark = Color(0x14FFFFFF);
  static const Color outlineVariantDark = Color(0x0AFFFFFF);

  // ===== Semantic =====
  static const Color errorLight = Color(0xFFFF453A); // iOS Red
  static const Color errorDark = Color(0xFFFF6961);
  static const Color warningLight = Color(0xFFFF9F0A); // iOS Orange
  static const Color warningDark = Color(0xFFFFB340);
  static const Color successLight = Color(0xFF30D158); // iOS Green
  static const Color successDark = Color(0xFF30D158);

  // ===== Glass Overlay =====
  static const Color surfaceOverlayLight = Color(0xB3FFFFFF);
  static const Color surfaceOverlayDark = Color(0xBF2C2C2E);
  static const Color surfacePressedDark = Color(0xFF48484A);

  // ===== UI Elements (Light) =====
  static const Color sidebarLight = Color(0xFFEEEEEE);
  static const Color bottomBarLight = Color(0xFFFAFAFA);
  static const Color panelLight = Color(0xFFF5F5F5);
  static const Color selectedItemLight = Color(0xFFFFFFFF);
  static const Color searchFieldLight = Color(0xFFFFFFFF);
  static const Color playBarLight = Color(0xFFFFFFFF);
  static const Color seekBarActiveLight = Color(0xFF1A1A1A);
  static const Color volumeBarActiveLight = Color(0xFF1A1A1A);

  // ===== UI Elements (Dark) =====
  static const Color sidebarDark = Color(0xFF373737);
  static const Color bottomBarDark = Color(0xFF3C3C3C);
  static const Color panelDark = Color(0xFF323232);
  static const Color selectedItemDark = Color(0xFF464646);
  static const Color searchFieldDark = Color(0xFF4A4A4A);
  static const Color playBarDark = Color(0xFF3C3C3C);
  static const Color seekBarActiveDark = Color(0xFF9A9A9A);
  static const Color volumeBarActiveDark = Color(0xFF9A9A9A);
}

AppPalette _lucentPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: LucentColors.sidebarLight,
      bottomBar: LucentColors.bottomBarLight,
      panelSurface: LucentColors.panelLight,
      selectedItem: LucentColors.selectedItemLight,
      searchField: LucentColors.searchFieldLight,
      playBar: LucentColors.playBarLight,
      seekBarActive: LucentColors.seekBarActiveLight,
      volumeBarActive: LucentColors.volumeBarActiveLight,
      surfaceOverlay: LucentColors.surfaceOverlayLight,
      surfaceHover: LucentColors.surfaceContainerLight,
      surfacePressed: LucentColors.surfaceContainerHighLight,
    );
  }
  return const AppPalette(
    sidebarSurface: LucentColors.sidebarDark,
    bottomBar: LucentColors.bottomBarDark,
    panelSurface: LucentColors.panelDark,
    selectedItem: LucentColors.selectedItemDark,
    searchField: LucentColors.searchFieldDark,
    playBar: LucentColors.playBarDark,
    seekBarActive: LucentColors.seekBarActiveDark,
    volumeBarActive: LucentColors.volumeBarActiveDark,
    surfaceOverlay: LucentColors.surfaceOverlayDark,
    surfaceHover: LucentColors.surfaceContainerDark,
    surfacePressed: LucentColors.surfacePressedDark,
  );
}

ColorScheme _lucentColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: LucentColors.primaryLight,
      onPrimary: Colors.white,
      secondary: LucentColors.secondaryLight,
      onSecondary: Colors.white,
      tertiary: LucentColors.secondaryLight,
      onTertiary: Colors.white,
      error: LucentColors.errorLight,
      onError: Colors.white,
      surface: LucentColors.surfaceLight,
      onSurface: LucentColors.onSurfaceLight,
      onSurfaceVariant: LucentColors.onSurfaceVariantLight,
      surfaceContainerLowest: LucentColors.surfaceLight,
      surfaceContainerLow: LucentColors.surfaceLight,
      surfaceContainer: LucentColors.surfaceContainerLight,
      surfaceContainerHigh: LucentColors.surfaceContainerHighLight,
      surfaceContainerHighest: LucentColors.surfaceRaisedLight,
      outline: LucentColors.outlineLight,
      outlineVariant: LucentColors.outlineVariantLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: LucentColors.onSurfaceLight,
      onInverseSurface: LucentColors.surfaceLight,
      inversePrimary: LucentColors.primaryDark,
      surfaceTint: LucentColors.primaryLight,
    );
  }
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: LucentColors.primaryDark,
    onPrimary: Colors.black,
    secondary: LucentColors.secondaryDark,
    onSecondary: Colors.black,
    tertiary: LucentColors.secondaryDark,
    onTertiary: Colors.black,
    error: LucentColors.errorDark,
    onError: Colors.black,
    surface: LucentColors.surfaceDark,
    onSurface: LucentColors.onSurfaceDark,
    onSurfaceVariant: LucentColors.onSurfaceVariantDark,
    surfaceContainerLowest: LucentColors.surfaceDark,
    surfaceContainerLow: LucentColors.surfaceDark,
    surfaceContainer: LucentColors.surfaceContainerDark,
    surfaceContainerHigh: LucentColors.surfaceContainerHighDark,
    surfaceContainerHighest: LucentColors.surfaceRaisedDark,
    outline: LucentColors.outlineDark,
    outlineVariant: LucentColors.outlineVariantDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: LucentColors.onSurfaceDark,
    onInverseSurface: LucentColors.surfaceDark,
    inversePrimary: LucentColors.primaryLight,
    surfaceTint: LucentColors.primaryDark,
  );
}

ThemeData _buildLucent(Brightness brightness) {
  final scheme = _lucentColorScheme(brightness);
  final palette = _lucentPalette(brightness);
  final accent = brightness == Brightness.light
      ? LucentColors.primaryLight
      : LucentColors.primaryDark;

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
      color: brightness == Brightness.light
          ? LucentColors.surfaceRaisedLight
          : LucentColors.surfaceRaisedDark,
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
      ),
      filled: true,
      fillColor: brightness == Brightness.light
          ? LucentColors.surfaceLight
          : LucentColors.surfaceDark,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? LucentColors.surfaceLight
        : LucentColors.surfaceDark,
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: brightness == Brightness.light
          ? LucentColors.outlineLight
          : LucentColors.outlineDark,
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.12),
    ),
    dividerColor: brightness == Brightness.light
        ? LucentColors.outlineLight
        : LucentColors.outlineDark,
  );
}

/// Lucent Theme factory for Flutter ThemeData
abstract class LucentTheme {
  static ThemeData lightTheme() => _buildLucent(Brightness.light);
  static ThemeData darkTheme() => _buildLucent(Brightness.dark);
}
