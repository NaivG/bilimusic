import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// Nocturne 主题颜色常量 —— 极简风格,白底/真黑底 + 单点深空蓝 accent。
/// 参考 `tessera/lib/ui/theme/tokens.dart` 设计稿。
abstract class NocturneColors {
  // ===== Accent =====
  static const Color primaryLight = Color(0xFF0A84FF);
  static const Color primaryDark = Color(0xFF409CFF);

  // ===== Surface (Light) =====
  static const Color surfaceLight = Color(0xFFFAFAFA);
  static const Color surfaceContainerLight = Color(0xFFF2F2F2);
  static const Color surfaceContainerHighLight = Color(0xFFE8E8E8);

  // ===== Surface (Dark) =====
  static const Color surfaceDark = Color(0xFF000000);
  static const Color surfaceContainerDark = Color(0xFF1C1C1E);
  static const Color surfaceContainerHighDark = Color(0xFF2C2C2E);

  // ===== Text (Light) =====
  static const Color onSurfaceLight = Color(0xFF1C1C1E);
  static const Color onSurfaceVariantLight = Color(0xFF6E6E73);

  // ===== Text (Dark) =====
  static const Color onSurfaceDark = Color(0xFFF2F2F7);
  static const Color onSurfaceVariantDark = Color(0xFF98989D);

  // ===== Outline =====
  static const Color outlineLight = Color(0x14000000);
  static const Color outlineVariantLight = Color(0x0A000000);
  static const Color outlineDark = Color(0x1FFFFFFF);
  static const Color outlineVariantDark = Color(0x0FFFFFFF);

  // ===== Semantic =====
  static const Color errorLight = Color(0xFFC0392B);
  static const Color errorDark = Color(0xFFFF6961);
  static const Color successLight = Color(0xFF1A8754);
  static const Color successDark = Color(0xFF30D158);
}

AppPalette _nocturnePalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: NocturneColors.surfaceContainerLight,
      bottomBar: NocturneColors.surfaceContainerLight,
      panelSurface: NocturneColors.surfaceContainerLight,
      selectedItem: NocturneColors.surfaceContainerHighLight,
      searchField: NocturneColors.surfaceContainerLight,
      playBar: NocturneColors.surfaceContainerLight,
      seekBarActive: NocturneColors.onSurfaceLight,
      volumeBarActive: NocturneColors.onSurfaceLight,
      surfaceOverlay: Color(0xCCFFFFFF),
      surfaceHover: NocturneColors.surfaceContainerHighLight,
      surfacePressed: NocturneColors.surfaceContainerHighLight,
    );
  }
  return const AppPalette(
    sidebarSurface: NocturneColors.surfaceContainerDark,
    bottomBar: NocturneColors.surfaceContainerDark,
    panelSurface: NocturneColors.surfaceContainerDark,
    selectedItem: NocturneColors.surfaceContainerHighDark,
    searchField: NocturneColors.surfaceContainerDark,
    playBar: NocturneColors.surfaceContainerDark,
    seekBarActive: NocturneColors.onSurfaceVariantDark,
    volumeBarActive: NocturneColors.onSurfaceVariantDark,
    surfaceOverlay: Color(0xBF000000),
    surfaceHover: NocturneColors.surfaceContainerHighDark,
    surfacePressed: NocturneColors.surfaceContainerHighDark,
  );
}

ColorScheme _nocturneColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: NocturneColors.primaryLight,
      onPrimary: Colors.white,
      secondary: NocturneColors.primaryLight,
      onSecondary: Colors.white,
      tertiary: NocturneColors.primaryLight,
      onTertiary: Colors.white,
      error: NocturneColors.errorLight,
      onError: Colors.white,
      surface: NocturneColors.surfaceLight,
      onSurface: NocturneColors.onSurfaceLight,
      onSurfaceVariant: NocturneColors.onSurfaceVariantLight,
      surfaceContainerLowest: NocturneColors.surfaceLight,
      surfaceContainerLow: NocturneColors.surfaceLight,
      surfaceContainer: NocturneColors.surfaceContainerLight,
      surfaceContainerHigh: NocturneColors.surfaceContainerHighLight,
      surfaceContainerHighest: NocturneColors.surfaceContainerHighLight,
      outline: NocturneColors.outlineLight,
      outlineVariant: NocturneColors.outlineVariantLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: NocturneColors.onSurfaceLight,
      onInverseSurface: NocturneColors.surfaceLight,
      inversePrimary: NocturneColors.primaryDark,
      surfaceTint: NocturneColors.primaryLight,
    );
  }
  return ColorScheme(
    brightness: Brightness.dark,
    primary: NocturneColors.primaryDark,
    onPrimary: Colors.black,
    secondary: NocturneColors.primaryDark,
    onSecondary: Colors.black,
    tertiary: NocturneColors.primaryDark,
    onTertiary: Colors.black,
    error: NocturneColors.errorDark,
    onError: Colors.black,
    surface: NocturneColors.surfaceDark,
    onSurface: NocturneColors.onSurfaceDark,
    onSurfaceVariant: NocturneColors.onSurfaceVariantDark,
    surfaceContainerLowest: NocturneColors.surfaceDark,
    surfaceContainerLow: NocturneColors.surfaceDark,
    surfaceContainer: NocturneColors.surfaceContainerDark,
    surfaceContainerHigh: NocturneColors.surfaceContainerHighDark,
    surfaceContainerHighest: NocturneColors.surfaceContainerHighDark,
    outline: NocturneColors.outlineDark,
    outlineVariant: NocturneColors.outlineVariantDark,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: NocturneColors.onSurfaceDark,
    onInverseSurface: NocturneColors.surfaceDark,
    inversePrimary: NocturneColors.primaryLight,
    surfaceTint: NocturneColors.primaryDark,
  );
}

ThemeData _buildNocturne(Brightness brightness) {
  final scheme = _nocturneColorScheme(brightness);
  final palette = _nocturnePalette(brightness);

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

/// Nocturne Theme factory for Flutter ThemeData
abstract class NocturneTheme {
  static ThemeData lightTheme() => _buildNocturne(Brightness.light);
  static ThemeData darkTheme() => _buildNocturne(Brightness.dark);
}
