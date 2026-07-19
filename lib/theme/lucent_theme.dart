import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// Lucent Theme 颜色常量 —— 仅 Lucent 主题内部使用。
/// 跨主题共享的颜色请通过 [AppPalette] 读取。
abstract class LucentColors {
  // ===== Surface (Light) =====
  static const Color lightSurfaceBase = Color(0xFFFAF9F7);
  static const Color lightSurfaceRaised = Color(0xFFFFFFFF);
  static const Color lightSurfaceHover = Color(0xFFF5F4F2);
  static const Color lightSurfacePressed = Color(0xFFECEAE7);

  // ===== Surface (Dark) =====
  static const Color darkSurfaceBase = Color(0xFF1C1C1E);
  static const Color darkSurfaceRaised = Color(0xFF2C2C2E);
  static const Color darkSurfaceHover = Color(0xFF3A3A3C);
  static const Color darkSurfacePressed = Color(0xFF48484A);

  // ===== Text (Light) =====
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF6E6E73);
  static const Color lightTextTertiary = Color(0xFFA1A1A6);

  // ===== Text (Dark) =====
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF98989D);
  static const Color darkTextTertiary = Color(0xFF6E6E73);

  // ===== Accent =====
  static const Color accentPrimary = Color(0xFF5E5CE6);
  static const Color accentSecondary = Color(0xFFBF5AF2);
  static const Color accentWarning = Color(0xFFFF9F0A);
  static const Color accentError = Color(0xFFFF453A);
  static const Color accentSuccess = Color(0xFF30D158);

  // ===== Border =====
  static const Color lightBorderSubtle = Color(0x0F000000);
  static const Color darkBorderSubtle = Color(0x14FFFFFF);

  // ===== Glass overlay =====
  static const Color lightSurfaceOverlay = Color(0xB3FFFFFF);
  static const Color darkSurfaceOverlay = Color(0xBF2C2C2E);

  // ===== UI Elements (Light) =====
  static const Color lightSidebarSurface = Color(0xFFEEEEEE);
  static const Color lightBottomBar = Color(0xFFFAFAFA);
  static const Color lightPanelSurface = Color(0xFFF5F5F5);
  static const Color lightSelectedItem = Color(0xFFFFFFFF);
  static const Color lightSearchField = Color(0xFFFFFFFF);
  static const Color lightPlayBar = Color(0xFFFFFFFF);

  // ===== UI Elements (Dark) =====
  static const Color darkSidebarSurface = Color(0xFF373737);
  static const Color darkBottomBar = Color(0xFF3C3C3C);
  static const Color darkPanelSurface = Color(0xFF323232);
  static const Color darkSelectedItem = Color(0xFF464646);
  static const Color darkSearchField = Color(0xFF4A4A4A);
  static const Color darkPlayBar = Color(0xFF3C3C3C);

  // ===== Seek / Volume =====
  static const Color lightSeekBarActive = Color(0xFF1A1A1A);
  static const Color darkSeekBarActive = Color(0xFF9A9A9A);
  static const Color lightVolumeBarActive = Color(0xFF1A1A1A);
  static const Color darkVolumeBarActive = Color(0xFF9A9A9A);
}

AppPalette _lucentPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: LucentColors.lightSidebarSurface,
      bottomBar: LucentColors.lightBottomBar,
      panelSurface: LucentColors.lightPanelSurface,
      selectedItem: LucentColors.lightSelectedItem,
      searchField: LucentColors.lightSearchField,
      playBar: LucentColors.lightPlayBar,
      seekBarActive: LucentColors.lightSeekBarActive,
      volumeBarActive: LucentColors.lightVolumeBarActive,
      surfaceOverlay: LucentColors.lightSurfaceOverlay,
      surfaceHover: LucentColors.lightSurfaceHover,
      surfacePressed: LucentColors.lightSurfacePressed,
    );
  }
  return const AppPalette(
    sidebarSurface: LucentColors.darkSidebarSurface,
    bottomBar: LucentColors.darkBottomBar,
    panelSurface: LucentColors.darkPanelSurface,
    selectedItem: LucentColors.darkSelectedItem,
    searchField: LucentColors.darkSearchField,
    playBar: LucentColors.darkPlayBar,
    seekBarActive: LucentColors.darkSeekBarActive,
    volumeBarActive: LucentColors.darkVolumeBarActive,
    surfaceOverlay: LucentColors.darkSurfaceOverlay,
    surfaceHover: LucentColors.darkSurfaceHover,
    surfacePressed: LucentColors.darkSurfacePressed,
  );
}

ColorScheme _lucentColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: LucentColors.accentPrimary,
      onPrimary: Colors.white,
      secondary: LucentColors.accentSecondary,
      onSecondary: Colors.white,
      error: LucentColors.accentError,
      onError: Colors.white,
      surface: LucentColors.lightSurfaceBase,
      onSurface: LucentColors.lightTextPrimary,
      surfaceContainerHighest: LucentColors.lightSurfaceRaised,
      outline: LucentColors.lightBorderSubtle,
    );
  }
  return ColorScheme(
    brightness: Brightness.dark,
    primary: LucentColors.accentPrimary,
    onPrimary: Colors.white,
    secondary: LucentColors.accentSecondary,
    onSecondary: Colors.white,
    error: LucentColors.accentError,
    onError: Colors.white,
    surface: LucentColors.darkSurfaceBase,
    onSurface: LucentColors.darkTextPrimary,
    surfaceContainerHighest: LucentColors.darkSurfaceRaised,
    outline: LucentColors.darkBorderSubtle,
  );
}

ThemeData _buildLucent(Brightness brightness) {
  final scheme = _lucentColorScheme(brightness);
  final palette = _lucentPalette(brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [palette],
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      elevation: 0,
      color: brightness == Brightness.light
          ? LucentColors.lightSurfaceRaised
          : LucentColors.darkSurfaceRaised,
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
          ? LucentColors.lightSurfaceBase
          : LucentColors.darkSurfaceBase,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? LucentColors.lightSurfaceBase
        : LucentColors.darkSurfaceBase,
    sliderTheme: SliderThemeData(
      activeTrackColor: LucentColors.accentPrimary,
      inactiveTrackColor: brightness == Brightness.light
          ? LucentColors.lightBorderSubtle
          : LucentColors.darkBorderSubtle,
      thumbColor: LucentColors.accentPrimary,
      overlayColor: LucentColors.accentPrimary.withValues(alpha: 0.12),
    ),
    dividerColor: brightness == Brightness.light
        ? LucentColors.lightBorderSubtle
        : LucentColors.darkBorderSubtle,
  );
}

/// Lucent Theme factory for Flutter ThemeData
abstract class LucentTheme {
  static ThemeData lightTheme() => _buildLucent(Brightness.light);
  static ThemeData darkTheme() => _buildLucent(Brightness.dark);
}