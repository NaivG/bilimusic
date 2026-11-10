import 'package:flutter/material.dart';

import '../ui/theme/bm_theme.dart';
import 'app_palette.dart';

/// Theater 主题色值 —— 暖纸白 + 墨黑 + 湖水青 + 舞台金。
///
/// 结构方向（间距 / 行高 / 组件形态）全部由 token 决定，这里只给色值；
/// 跨主题共享的颜色通过 [AppPalette] 读取。
abstract class TheaterColors {
  // ===== 舞台纸面（Light）=====
  /// 页面底：暖纸白。
  static const Color paper = Color(0xFFF8F3E7);

  /// 次级面：占位图、输入槽。
  static const Color paperDeep = Color(0xFFEFE7D7);

  /// 卡片 / 白卡。
  static const Color card = Color(0xFFFFFFFF);

  /// 浮层 / Sheet（比纸更白一点）。
  static const Color sheet = Color(0xFFFCFAF4);

  /// 主文字：墨黑。
  static const Color ink = Color(0xFF171614);

  /// 次级文字（纸面 5.09:1）。
  static const Color sub = Color(0xFF6B675E);

  /// 舞台金。
  static const Color gold = Color(0xFFF0CD56);

  // ===== 主色 =====
  /// 湖水青。
  static const Color teal = Color(0xFF1F8A94);

  /// 深湖水青（选中文字、图标底座）。
  static const Color tealDeep = Color(0xFF146E78);

  // ===== 语义 =====
  static const Color danger = Color(0xFFB9553F);
  static const Color warning = Color(0xFFC98410);
  static const Color success = Color(0xFF2FA36B);

  // ===== 描边 =====
  /// `rgba(23,22,20,.08)`。
  static const Color line = Color(0x14171614);

  /// `rgba(23,22,20,.14)`。
  static const Color lineStrong = Color(0x24171614);

  // ===== 暗色舞台 =====
  static const Color stageBlack = Color(0xFF141210);
  static const Color stageBlackLow = Color(0xFF191713);
  static const Color stageBlackMid = Color(0xFF1E1B17);
  static const Color stageBlackHigh = Color(0xFF262219);
  static const Color stageBlackHighest = Color(0xFF2E2921);
  static const Color stageInk = Color(0xFFF5F0E6);
  static const Color stageSub = Color(0xFFA39C8F);
  static const Color stageTeal = Color(0xFF4DBAC4);
  static const Color stageTealDeep = Color(0xFF7FD4DB);
  static const Color stageDanger = Color(0xFFE0755C);
  static const Color stageWarning = Color(0xFFE3A03C);
  static const Color stageSuccess = Color(0xFF4FBF88);
  static const Color stageLine = Color(0x14F5F0E6);
  static const Color stageLineStrong = Color(0x24F5F0E6);

  // ===== 纸面阶梯 =====
  static const Color paperLow = Color(0xFFF4EDDD);
  static const Color paperLowest = Color(0xFFFBF8EF);

  /// hover 状态层落到纸面上的近似色（`surfaceHover`）。
  static const Color paperHover = Color(0xFFF0E9DB);

  /// pressed 状态层落到纸面上的近似色。
  static const Color paperPressed = Color(0xFFE8E0CF);

  /// 贴边栏的半透明白（`surfaceOverlay`）。
  static const Color overlayLight = Color(0xD1FFFFFF);
  static const Color overlayDark = Color(0xD1262219);
}

AppPalette _theaterPalette(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const AppPalette(
      sidebarSurface: TheaterColors.paperDeep,
      bottomBar: TheaterColors.sheet,
      panelSurface: TheaterColors.card,
      selectedItem: TheaterColors.card,
      searchField: TheaterColors.card,
      playBar: TheaterColors.sheet,
      seekBarActive: TheaterColors.teal,
      volumeBarActive: TheaterColors.teal,
      warning: TheaterColors.warning,
      success: TheaterColors.success,
      surfaceOverlay: TheaterColors.overlayLight,
      surfaceHover: TheaterColors.paperHover,
      surfacePressed: TheaterColors.paperPressed,
    );
  }
  return const AppPalette(
    sidebarSurface: TheaterColors.stageBlackMid,
    bottomBar: TheaterColors.stageBlackLow,
    panelSurface: TheaterColors.stageBlackHigh,
    selectedItem: TheaterColors.stageBlackHighest,
    searchField: TheaterColors.stageBlackMid,
    playBar: TheaterColors.stageBlackLow,
    seekBarActive: TheaterColors.stageTeal,
    volumeBarActive: TheaterColors.stageTeal,
    warning: TheaterColors.stageWarning,
    success: TheaterColors.stageSuccess,
    surfaceOverlay: TheaterColors.overlayDark,
    surfaceHover: TheaterColors.stageBlackHigh,
    surfacePressed: TheaterColors.stageBlackHighest,
  );
}

ColorScheme _theaterColorScheme(Brightness brightness) {
  if (brightness == Brightness.light) {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: TheaterColors.teal,
      onPrimary: Colors.white,
      secondary: TheaterColors.tealDeep,
      onSecondary: Colors.white,
      tertiary: TheaterColors.gold,
      onTertiary: TheaterColors.ink,
      error: TheaterColors.danger,
      onError: Colors.white,
      surface: TheaterColors.paper,
      onSurface: TheaterColors.ink,
      onSurfaceVariant: TheaterColors.sub,
      surfaceContainerLowest: TheaterColors.paperLowest,
      surfaceContainerLow: TheaterColors.paperLow,
      surfaceContainer: TheaterColors.paperDeep,
      surfaceContainerHigh: TheaterColors.sheet,
      surfaceContainerHighest: TheaterColors.card,
      outline: TheaterColors.lineStrong,
      outlineVariant: TheaterColors.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: TheaterColors.ink,
      onInverseSurface: TheaterColors.paper,
      inversePrimary: TheaterColors.stageTeal,
      surfaceTint: TheaterColors.teal,
    );
  }
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: TheaterColors.stageTeal,
    onPrimary: Color(0xFF082024),
    secondary: TheaterColors.stageTealDeep,
    onSecondary: Color(0xFF082024),
    tertiary: TheaterColors.gold,
    onTertiary: Color(0xFF1A1712),
    error: TheaterColors.stageDanger,
    onError: Color(0xFF1A0E0A),
    surface: TheaterColors.stageBlack,
    onSurface: TheaterColors.stageInk,
    onSurfaceVariant: TheaterColors.stageSub,
    surfaceContainerLowest: Color(0xFF0F0E0C),
    surfaceContainerLow: TheaterColors.stageBlackLow,
    surfaceContainer: TheaterColors.stageBlackMid,
    surfaceContainerHigh: TheaterColors.stageBlackHigh,
    surfaceContainerHighest: TheaterColors.stageBlackHighest,
    outline: TheaterColors.stageLineStrong,
    outlineVariant: TheaterColors.stageLine,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: TheaterColors.stageInk,
    onInverseSurface: TheaterColors.stageBlack,
    inversePrimary: TheaterColors.teal,
    surfaceTint: TheaterColors.stageTeal,
  );
}

ThemeData _buildTheater(Brightness brightness) {
  return BmTheme.build(
    scheme: _theaterColorScheme(brightness),
    palette: _theaterPalette(brightness),
  );
}

/// Theater 主题工厂。
abstract class TheaterTheme {
  static ThemeData lightTheme() => _buildTheater(Brightness.light);
  static ThemeData darkTheme() => _buildTheater(Brightness.dark);
}
