import 'package:flutter/material.dart';

/// 主题扩展调色板 —— 承载 M3 [ColorScheme] 之外但组件在用的颜色。
///
/// 通过 [ThemeData.extensions] 注入,组件通过
/// `Theme.of(context).extension<AppPalette>()` 读取,实现主题切换真正生效。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  // ===== Sidebar / BottomBar / Panel =====
  final Color sidebarSurface;
  final Color bottomBar;
  final Color panelSurface;
  final Color selectedItem;
  final Color searchField;
  final Color playBar;

  // ===== Seek / Volume =====
  final Color seekBarActive;
  final Color volumeBarActive;

  // ===== Glass Overlay (semi-transparent, 用于 BackdropFilter 容器) =====
  final Color surfaceOverlay;
  final Color surfaceHover;
  final Color surfacePressed;

  const AppPalette({
    required this.sidebarSurface,
    required this.bottomBar,
    required this.panelSurface,
    required this.selectedItem,
    required this.searchField,
    required this.playBar,
    required this.seekBarActive,
    required this.volumeBarActive,
    required this.surfaceOverlay,
    required this.surfaceHover,
    required this.surfacePressed,
  });

  @override
  AppPalette copyWith({
    Color? sidebarSurface,
    Color? bottomBar,
    Color? panelSurface,
    Color? selectedItem,
    Color? searchField,
    Color? playBar,
    Color? seekBarActive,
    Color? volumeBarActive,
    Color? surfaceOverlay,
    Color? surfaceHover,
    Color? surfacePressed,
  }) {
    return AppPalette(
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      bottomBar: bottomBar ?? this.bottomBar,
      panelSurface: panelSurface ?? this.panelSurface,
      selectedItem: selectedItem ?? this.selectedItem,
      searchField: searchField ?? this.searchField,
      playBar: playBar ?? this.playBar,
      seekBarActive: seekBarActive ?? this.seekBarActive,
      volumeBarActive: volumeBarActive ?? this.volumeBarActive,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfacePressed: surfacePressed ?? this.surfacePressed,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      sidebarSurface: Color.lerp(sidebarSurface, other.sidebarSurface, t)!,
      bottomBar: Color.lerp(bottomBar, other.bottomBar, t)!,
      panelSurface: Color.lerp(panelSurface, other.panelSurface, t)!,
      selectedItem: Color.lerp(selectedItem, other.selectedItem, t)!,
      searchField: Color.lerp(searchField, other.searchField, t)!,
      playBar: Color.lerp(playBar, other.playBar, t)!,
      seekBarActive: Color.lerp(seekBarActive, other.seekBarActive, t)!,
      volumeBarActive: Color.lerp(volumeBarActive, other.volumeBarActive, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// 当前主题注入的 [AppPalette]。若 Theme 未注入则按亮色 fallback,以保证
  /// 预览/早期 build 阶段不抛异常。
  AppPalette get appPalette =>
      Theme.of(this).extension<AppPalette>() ?? AppPaletteFallback.light;
}

/// 仅在 Theme 尚未注入 AppPalette 的早期 build 阶段作为安全网。
class AppPaletteFallback {
  static const AppPalette light = AppPalette(
    sidebarSurface: Color(0xFFEEEEEE),
    bottomBar: Color(0xFFFAFAFA),
    panelSurface: Color(0xFFF5F5F5),
    selectedItem: Color(0xFFFFFFFF),
    searchField: Color(0xFFFFFFFF),
    playBar: Color(0xFFFFFFFF),
    seekBarActive: Color(0xFF1A1A1A),
    volumeBarActive: Color(0xFF1A1A1A),
    surfaceOverlay: Color(0xB3FFFFFF),
    surfaceHover: Color(0xFFF5F4F2),
    surfacePressed: Color(0xFFECEAE7),
  );
}