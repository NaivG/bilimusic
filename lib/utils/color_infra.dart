import 'package:flutter/material.dart';

/// 全局颜色状态管理

// ===================================== 颜色更新通知器 =====================================

/// 颜色更新通知器 - 当封面颜色变化时通知所有监听器重建UI
final updateColorNotifier = ValueNotifier<int>(0);

/// 主题模式通知器 - 0=vivid, 1=light, 2=dark
final mainPageThemeNotifier = ValueNotifier<int>(0);

// ===================================== 颜色变量 =====================================

/// 背景封面主色调
Color backgroundBaseColor = Colors.grey;

/// 封面提取的主题色
Color coverArtColor = Colors.grey;

/// 页面背景色
Color backgroundColor = Colors.grey.shade200;

/// 图标色
Color iconColor = Colors.black;

/// 文本色
Color textColor = Colors.grey.shade900;

/// 高亮文本色
Color highlightTextColor = Colors.black;

/// 侧边栏背景色
Color sidebarColor = Colors.grey.shade200;

/// 底部控制栏背景色
Color bottomColor = Colors.grey.shade50;

/// 进度条激活色
Color seekBarColor = Colors.black;

/// 音量条激活色
Color volumeBarColor = Colors.black;

/// 面板背景色
Color panelColor = Colors.grey.shade100;

/// 选中项颜色
Color selectedItemColor = Colors.white;

/// 分割线颜色
Color dividerColor = Colors.grey;

/// 搜索框背景色
Color searchFieldColor = Colors.white;

/// 按钮颜色
Color buttonColor = Colors.black;

/// 播放栏颜色
Color playBarColor = Colors.white;

/// Helper getters
bool get isVividMode => mainPageThemeNotifier.value == 0;
bool get isLightMode => mainPageThemeNotifier.value == 1;
bool get isDarkMode => mainPageThemeNotifier.value == 2;

/// 更新所有颜色（根据主题模式和封面颜色）
void updateColors({
  required bool isDark,
  Color? coverColor,
}) {
  if (isDark) {
    backgroundColor = const Color(0xFF323232);
    iconColor = Colors.grey.shade400;
    textColor = Colors.grey.shade400;
    highlightTextColor = const Color(0xFFE6E6E6);
    sidebarColor = const Color(0xFF373737);
    bottomColor = const Color(0xFF3C3C3C);
    panelColor = const Color(0xFF323232);
    seekBarColor = Colors.grey.shade400;
    volumeBarColor = Colors.grey.shade400;
    selectedItemColor = const Color(0xFF464646);
    dividerColor = Colors.grey.shade700;
    searchFieldColor = Colors.grey.shade700;
    buttonColor = Colors.grey.shade400;
    playBarColor = const Color(0xFF3C3C3C);
  } else {
    backgroundColor = const Color(0xFFF5F5F5);
    iconColor = Colors.black;
    textColor = Colors.grey.shade900;
    highlightTextColor = Colors.black;
    sidebarColor = const Color(0xFFEEEEEE);
    bottomColor = const Color(0xFFFAFAFA);
    panelColor = const Color(0xFFF5F5F5);
    seekBarColor = Colors.black;
    volumeBarColor = Colors.black;
    selectedItemColor = Colors.white;
    dividerColor = Colors.grey.shade400;
    searchFieldColor = Colors.white;
    buttonColor = Colors.black;
    playBarColor = Colors.white;
  }

  if (coverColor != null) {
    coverArtColor = coverColor;
    // Vivid模式下使用封面颜色作为选中色
    if (isVividMode) {
      selectedItemColor = coverColor;
    }
  }

  updateColorNotifier.value++;
}
