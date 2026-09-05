import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// Verdant 主题颜色常量 —— 自然风格,米纸暖白底/深墨绿底 + 青竹绿 accent。
abstract class VerdantColors {
  // ===== Accent =====
  static const Color primaryLight = Color(0xFF4C7A5A); // 苔绿
  static const Color primaryDark = Color(0xFF6FBF8C); // 竹青

  // ===== Surface (Light) —— 米纸暖白阶梯 =====
  static const Color surfaceLight = Color(0xFFF6F4EE);
  static const Color surfaceContainerLight = Color(0xFFEDEBE1);
  static const Color surfaceContainerHighLight = Color(0xFFE2DFD2);

  // ===== Surface (Dark) —— 深墨绿阶梯 =====
  static const Color surfaceDark = Color(0xFF10160F);
  static const Color surfaceContainerDark = Color(0xFF19211A);
  static const Color surfaceContainerHighDark = Color(0xFF232D23);

  // ===== Text (Light) =====
  static const Color onSurfaceLight = Color(0xFF1E2A20); // 墨绿炭黑
  static const Color onSurfaceVariantLight = Color(0xFF5E6B5F); // 苔灰

  // ===== Text (Dark) =====
  static const Color onSurfaceDark = Color(0xFFE8EFE6); // 暖白带绿调
  static const Color onSurfaceVariantDark = Color(0xFF9AA89B);

  // ===== Outline —— 绿调低透明 =====
  static const Color outlineLight = Color(0x1A2E4632);
  static const Color outlineVariantLight = Color(0x0D2E4632);
  static const Color outlineDark = Color(0x1F6FBF8C);
  static const Color outlineVariantDark = Color(0x0F6FBF8C);

  // ===== Semantic =====
  static const Color errorLight = Color(0xFFC0392B);
  static const Color errorDark = Color(0xFFFF6961);
  static const Color successLight = Color(0xFF2E7D4F);
  static const Color successDark = Color(0xFF5FD08A);
}

AppPalette _verdantPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: VerdantColors.surfaceContainerLight,
      bottomBar: VerdantColors.surfaceContainerLight,
      panelSurface: VerdantColors.surfaceContainerLight,
      selectedItem: VerdantColors.surfaceContainerHighLight,
      searchField: VerdantColors.surfaceContainerLight,
      playBar: VerdantColors.surfaceContainerLight,
      seekBarActive: VerdantColors.onSurfaceLight,
      volumeBarActive: VerdantColors.onSurfaceLight,
      surfaceOverlay: Color(0xCCF6F4EE),
      surfaceHover: VerdantColors.surfaceContainerHighLight,
      surfacePressed: VerdantColors.surfaceContainerHighLight,
    );
  }
  return const AppPalette(
    sidebarSurface: VerdantColors.surfaceContainerDark,
    bottomBar: VerdantColors.surfaceContainerDark,
    panelSurface: VerdantColors.surfaceContainerDark,
    selectedItem: VerdantColors.surfaceContainerHighDark,
    searchField: VerdantColors.surfaceContainerDark,
    playBar: VerdantColors.surfaceContainerDark,
    seekBarActive: VerdantColors.onSurfaceVariantDark,
    volumeBarActive: VerdantColors.onSurfaceVariantDark,
    surfaceOverlay: Color(0xBF10160F),
    surfaceHover: VerdantColors.surfaceContainerHighDark,
    surfacePressed: VerdantColors.surfaceContainerHighDark,
  );
}

ColorScheme _verdantColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: VerdantColors.primaryLight,
      onPrimary: Colors.white,
      secondary: VerdantColors.primaryLight,
      onSecondary: Colors.white,
      tertiary: VerdantColors.primaryLight,
      onTertiary: Colors.white,
      error: VerdantColors.errorLight,
      onError: Colors.white,
      surface: VerdantColors.surfaceLight,
      onSurface: VerdantColors.onSurfaceLight,
      onSurfaceVariant: VerdantColors.onSurfaceVariantLight,
      surfaceContainerLowest: VerdantColors.surfaceLight,
      surfaceContainerLow: VerdantColors.surfaceLight,
      surfaceContainer: VerdantColors.surfaceContainerLight,
      surfaceContainerHigh: VerdantColors.surfaceContainerHighLight,
      surfaceContainerHighest: VerdantColors.surfaceContainerHighLight,
      outline: VerdantColors.outlineLight,
      outlineVariant: VerdantColors.outlineVariantLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: VerdantColors.onSurfaceLight,
      onInverseSurface: VerdantColors.surfaceLight,
      inversePrimary: VerdantColors.primaryDark,
      surfaceTint: VerdantColors.primaryLight,
    );
  }
  return ColorScheme(
    brightness: Brightness.dark,
    primary: VerdantColors.primaryDark,
    onPrimary: Colors.black,
    secondary: VerdantColors.primaryDark,
    onSecondary: Colors.black,
    tertiary: VerdantColors.primaryDark,
    onTertiary: Colors.black,
    error: VerdantColors.errorDark,
    onError: Colors.black,
    surface: VerdantColors.surfaceDark,
    onSurface: VerdantColors.onSurfaceDark,
    onSurfaceVariant: VerdantColors.onSurfaceVariantDark,
    surfaceContainerLowest: VerdantColors.surfaceDark,
    surfaceContainerLow: VerdantColors.surfaceDark,
    surfaceContainer: VerdantColors.surfaceContainerDark,
    surfaceContainerHigh: VerdantColors.surfaceContainerHighDark,
    surfaceContainerHighest: VerdantColors.surfaceContainerHighDark,
    outline: VerdantColors.outlineDark,
    outlineVariant: VerdantColors.outlineVariantDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: VerdantColors.onSurfaceDark,
    onInverseSurface: VerdantColors.surfaceDark,
    inversePrimary: VerdantColors.primaryLight,
    surfaceTint: VerdantColors.primaryDark,
  );
}

ThemeData _buildVerdant(Brightness brightness) {
  final scheme = _verdantColorScheme(brightness);
  final palette = _verdantPalette(brightness);

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

/// Verdant Theme factory for Flutter ThemeData
abstract class VerdantTheme {
  static ThemeData lightTheme() => _buildVerdant(Brightness.light);
  static ThemeData darkTheme() => _buildVerdant(Brightness.dark);
}
