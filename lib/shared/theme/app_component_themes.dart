import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 跨主题复用的「组件主题」工厂。
///
/// 放在这里而不是在六个主题文件里各写一遍：圆角、浮动行为、四边留白这些
/// 结构性样式与配色无关，主题只需要把自己的 [ColorScheme] 传进来。
abstract class AppComponentThemes {
  /// 全应用统一的 SnackBar（toast）样式：圆角 + 浮动 + 四边留白。
  ///
  /// 样式走主题而不是包一层 `showAppSnackBar` helper：调用点有上百处，
  /// 主题能一次性覆盖现有和以后所有 `ScaffoldMessenger.showSnackBar`，
  /// helper 只能管住被改过的调用点，漏一处就出现两种观感。
  ///
  /// 浮动样式不贴屏幕底边，配合外壳把播放条放进 Scaffold 底槽
  /// （见 `LandscapeShell` / `PortraitShell`），toast 会浮在迷你播放器 /
  /// 底部控制栏上方——[insetPadding] 的下边距就是两者之间的那道缝。
  ///
  /// 注意 [contentTextStyle] 必须显式给：SnackBar 默认按
  /// `onInverseSurface` 取色，而这里换成了 surfaceContainerHigh 底色，
  /// 不覆盖会在浅色主题下出现灰字压深底。
  static SnackBarThemeData snackBar(ColorScheme scheme) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        side: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      // 左右 16 让胶囊不顶边，底部 12 与底栏留一口气
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
      actionTextColor: scheme.primary,
      // 与 cardTheme / BottomNavigationBar 一致走平面风格，不要 M3 的高程染色
      elevation: 0,
    );
  }
}
