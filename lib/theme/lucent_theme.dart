import 'package:flutter/material.dart';

/// Lucent Design Language - Design Tokens
/// Based on Lucent design spec with no visible borders,
/// warm muted palette, and frosted glass effects.
abstract class LucentTokens {
  // ===== Surface Colors - Light Mode =====
  static const Color lightSurfaceBase = Color(0xFFFAF9F7);
  static const Color lightSurfaceRaised = Color(0xFFFFFFFF);
  static const Color lightSurfaceOverlay = Color(0xB3FFFFFF); // 72% white
  static const Color lightSurfaceHover = Color(0xFFF5F4F2);
  static const Color lightSurfacePressed = Color(0xFFECEAE7);

  // ===== Surface Colors - Dark Mode =====
  static const Color darkSurfaceBase = Color(0xFF1C1C1E);
  static const Color darkSurfaceRaised = Color(0xFF2C2C2E);
  static const Color darkSurfaceOverlay = Color(0xBF2C2C2E); // 75% dark
  static const Color darkSurfaceHover = Color(0xFF3A3A3C);
  static const Color darkSurfacePressed = Color(0xFF48484A);

  // ===== Text Colors - Light Mode =====
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF6E6E73);
  static const Color lightTextTertiary = Color(0xFFA1A1A6);

  // ===== Text Colors - Dark Mode =====
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF98989D);
  static const Color darkTextTertiary = Color(0xFF6E6E73);

  // ===== Accent Colors (same for both modes) =====
  static const Color accentPrimary = Color(0xFF5E5CE6);
  static const Color accentSecondary = Color(0xFFBF5AF2);
  static const Color accentWarning = Color(0xFFFF9F0A);
  static const Color accentError = Color(0xFFFF453A);
  static const Color accentSuccess = Color(0xFF30D158);

  // ===== Border Subtle =====
  static const Color lightBorderSubtle = Color(0x0F000000); // rgba(0,0,0,0.06)
  static const Color darkBorderSubtle = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

  // ===== Radius Tokens =====
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;

  // ===== Motion =====
  static const Curve standardEasing = Curves.easeOut;
  static const Curve decelerateEasing = Curves.easeIn;
  static const Curve accelerateEasing = Curves.easeOut;
  static const Duration microDuration = Duration(milliseconds: 100);
  static const Duration standardDuration = Duration(milliseconds: 200);
  static const Duration layoutDuration = Duration(milliseconds: 350);

  // ===== Glass Effect =====
  static const double glassBlurSigma = 20.0;
  static const double overlayBlurSigma = 24.0;
  static const double heavyGlassBlurSigma = 50.0;

  // ===== UI Element Colors - Light Mode =====
  static const Color lightSidebarSurface = Color(0xFFEEEEEE);
  static const Color lightBottomBar = Color(0xFFFAFAFA);
  static const Color lightPanelSurface = Color(0xFFF5F5F5);
  static const Color lightSelectedItem = Color(0xFFFFFFFF);
  static const Color lightSearchField = Color(0xFFFFFFFF);
  static const Color lightPlayBar = Color(0xFFFFFFFF);

  // ===== UI Element Colors - Dark Mode =====
  static const Color darkSidebarSurface = Color(0xFF373737);
  static const Color darkBottomBar = Color(0xFF3C3C3C);
  static const Color darkPanelSurface = Color(0xFF323232);
  static const Color darkSelectedItem = Color(0xFF464646);
  static const Color darkSearchField = Color(0xFF4A4A4A);
  static const Color darkPlayBar = Color(0xFF3C3C3C);

  // ===== Interactive Colors =====
  static const Color lightSeekBarActive = Color(0xFF1A1A1A);
  static const Color darkSeekBarActive = Color(0xFF9A9A9A);
  static const Color lightVolumeBarActive = Color(0xFF1A1A1A);
  static const Color darkVolumeBarActive = Color(0xFF9A9A9A);

  // ===== Helper to get surface colors based on brightness =====
  static Color surfaceBase(Brightness brightness) =>
      brightness == Brightness.light ? lightSurfaceBase : darkSurfaceBase;

  static Color surfaceRaised(Brightness brightness) =>
      brightness == Brightness.light ? lightSurfaceRaised : darkSurfaceRaised;

  static Color surfaceOverlay(Brightness brightness) =>
      brightness == Brightness.light ? lightSurfaceOverlay : darkSurfaceOverlay;

  static Color surfaceHover(Brightness brightness) =>
      brightness == Brightness.light ? lightSurfaceHover : darkSurfaceHover;

  static Color surfacePressed(Brightness brightness) =>
      brightness == Brightness.light ? lightSurfacePressed : darkSurfacePressed;

  static Color textPrimary(Brightness brightness) =>
      brightness == Brightness.light ? lightTextPrimary : darkTextPrimary;

  static Color textSecondary(Brightness brightness) =>
      brightness == Brightness.light ? lightTextSecondary : darkTextSecondary;

  static Color textTertiary(Brightness brightness) =>
      brightness == Brightness.light ? lightTextTertiary : darkTextTertiary;

  static Color borderSubtle(Brightness brightness) =>
      brightness == Brightness.light ? lightBorderSubtle : darkBorderSubtle;

  // ===== UI Element Color Helpers =====
  static Color sidebarSurface(Brightness brightness) =>
      brightness == Brightness.light ? lightSidebarSurface : darkSidebarSurface;

  static Color bottomBar(Brightness brightness) =>
      brightness == Brightness.light ? lightBottomBar : darkBottomBar;

  static Color panelSurface(Brightness brightness) =>
      brightness == Brightness.light ? lightPanelSurface : darkPanelSurface;

  static Color selectedItem(Brightness brightness) =>
      brightness == Brightness.light ? lightSelectedItem : darkSelectedItem;

  static Color searchField(Brightness brightness) =>
      brightness == Brightness.light ? lightSearchField : darkSearchField;

  static Color playBar(Brightness brightness) =>
      brightness == Brightness.light ? lightPlayBar : darkPlayBar;

  static Color seekBarActive(Brightness brightness) =>
      brightness == Brightness.light ? lightSeekBarActive : darkSeekBarActive;

  static Color volumeBarActive(Brightness brightness) =>
      brightness == Brightness.light ? lightVolumeBarActive : darkVolumeBarActive;
}

/// Lucent color scheme for Flutter ThemeData
abstract class LucentColorScheme {
  static ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: LucentTokens.accentPrimary,
    onPrimary: Colors.white,
    secondary: LucentTokens.accentSecondary,
    onSecondary: Colors.white,
    error: LucentTokens.accentError,
    onError: Colors.white,
    surface: LucentTokens.lightSurfaceBase,
    onSurface: LucentTokens.lightTextPrimary,
    surfaceContainerHighest: LucentTokens.lightSurfaceRaised,
    outline: LucentTokens.lightBorderSubtle,
  );

  static ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: LucentTokens.accentPrimary,
    onPrimary: Colors.white,
    secondary: LucentTokens.accentSecondary,
    onSecondary: Colors.white,
    error: LucentTokens.accentError,
    onError: Colors.white,
    surface: LucentTokens.darkSurfaceBase,
    onSurface: LucentTokens.darkTextPrimary,
    surfaceContainerHighest: LucentTokens.darkSurfaceRaised,
    outline: LucentTokens.darkBorderSubtle,
  );
}

/// Lucent Theme factory for Flutter ThemeData
abstract class LucentTheme {
  static ThemeData lightTheme() {
    return ThemeData(
      colorScheme: LucentColorScheme.lightColorScheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LucentTokens.radiusMd),
        ),
        elevation: 0,
        color: LucentTokens.lightSurfaceRaised,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LucentTokens.radiusSm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LucentTokens.radiusMd),
        ),
        filled: true,
        fillColor: LucentTokens.lightSurfaceBase,
      ),
      scaffoldBackgroundColor: LucentTokens.lightSurfaceBase,
      sliderTheme: SliderThemeData(
        activeTrackColor: LucentTokens.accentPrimary,
        inactiveTrackColor: LucentTokens.lightBorderSubtle,
        thumbColor: LucentTokens.accentPrimary,
        overlayColor: LucentTokens.accentPrimary.withValues(alpha: 0.12),
      ),
      dividerColor: LucentTokens.lightBorderSubtle,
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      colorScheme: LucentColorScheme.darkColorScheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LucentTokens.radiusMd),
        ),
        elevation: 0,
        color: LucentTokens.darkSurfaceRaised,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LucentTokens.radiusSm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LucentTokens.radiusMd),
        ),
        filled: true,
        fillColor: LucentTokens.darkSurfaceBase,
      ),
      scaffoldBackgroundColor: LucentTokens.darkSurfaceBase,
      sliderTheme: SliderThemeData(
        activeTrackColor: LucentTokens.accentPrimary,
        inactiveTrackColor: LucentTokens.darkBorderSubtle,
        thumbColor: LucentTokens.accentPrimary,
        overlayColor: LucentTokens.accentPrimary.withValues(alpha: 0.12),
      ),
      dividerColor: LucentTokens.darkBorderSubtle,
    );
  }
}
