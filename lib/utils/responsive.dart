import 'package:flutter/material.dart';

/// 屏幕尺寸分类
enum ScreenSize {
  /// 手机端：宽度 < 600dp
  mobile,

  /// 平板端：600dp ≤ 宽度 < 1200dp
  tablet,

  /// 桌面端：宽度 ≥ 1200dp
  desktop,
}

/// 响应式设计辅助工具类
class ResponsiveHelper {
  /// 获取当前屏幕尺寸分类
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return ScreenSize.desktop;
    if (width >= 600) return ScreenSize.tablet;
    return ScreenSize.mobile;
  }

  /// 根据屏幕尺寸返回不同的值
  static T responsiveValue<T>({
    required BuildContext context,
    required T mobile,
    required T tablet,
    required T desktop,
  }) {
    switch (getScreenSize(context)) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet;
      case ScreenSize.desktop:
        return desktop;
    }
  }

  /// 根据屏幕尺寸返回不同的列数（用于网格布局）
  static int responsiveGridColumns(BuildContext context) {
    return responsiveValue<int>(
      context: context,
      mobile: 2,
      tablet: 3,
      desktop: 5,
    );
  }

  /// 根据屏幕尺寸返回不同的间距
  static double responsiveSpacing(BuildContext context) {
    return responsiveValue<double>(
      context: context,
      mobile: 8.0,
      tablet: 12.0,
      desktop: 16.0,
    );
  }

}

/// 横屏布局断点定义
class LandscapeBreakpoints {
  /// 平板横屏最小宽度
  static const double tabletLandscapeMin = 600;

  /// 大平板横屏宽度
  static const double largeTabletMin = 900;

  /// 桌面横屏最小宽度
  static const double desktopMin = 1200;

  /// 检查是否为横屏模式（宽度大于高度且宽度 >= 600）
  static bool isLandscapeMode(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && size.width >= tabletLandscapeMin;
  }

  /// 是否启用横屏布局（横屏模式下且非竖屏手机）
  static bool shouldUseLandscapeLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 横屏布局：宽度 >= 600 且 宽度 > 高度
    return size.width >= tabletLandscapeMin && size.width > size.height;
  }

  /// 检查是否为竖屏模式
  static bool isPortraitMode(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.height >= size.width || size.width < tabletLandscapeMin;
  }

  /// 获取横屏封面尺寸（Apple Music 风格小封面）
  static double getCoverSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 260;
    if (width >= largeTabletMin) return 240;
    return 200;
  }

  /// 获取横屏控制条高度
  static double getControlsBarHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 140; // 这里反直觉的是在桌面端需要控制按钮小一些
    return 160; // 移动横屏端需要控制按钮大一些
  }

  /// 获取横屏歌词当前行字号（Apple Music 风格大字）
  static double getCurrentLyricFontSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 36;
    if (width >= largeTabletMin) return 30;
    return 24;
  }

  /// 获取横屏歌词其他行字号
  static double getOtherLyricFontSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 30;
    if (width >= largeTabletMin) return 26;
    return 22;
  }

  /// 获取横屏主播放按钮尺寸
  static double getMainPlayButtonSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 56;
    if (width >= largeTabletMin) return 52;
    return 44;
  }

  /// 获取横屏左侧区域比例（左列已自包含控制条，可适度缩窄）
  static double getLeftSectionRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 0.40;
    if (width >= largeTabletMin) return 0.38;
    return 0.36;
  }

  /// 获取横屏边距
  static double getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 48;
    if (width >= largeTabletMin) return 32;
    return 24;
  }
}

/// 异形小屏（手表/折叠外屏/近正方形 PiP）断点
class SquareBreakpoints {
  /// 最短边下界
  static const double squareMin = 200;

  /// 最短边上界（超过则视为正常手机/平板，不强制方屏布局）
  static const double squareMax = 500;

  /// 宽高比下界
  static const double ratioMin = 0.8;

  /// 宽高比上界
  static const double ratioMax = 1.25;

  /// 是否应使用方屏布局：
  /// 最短边在 [squareMin, squareMax] 区间，且宽高比在 [ratioMin, ratioMax] 区间
  static bool shouldUseSquareLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.shortestSide < squareMin || size.shortestSide > squareMax) {
      return false;
    }
    final ratio = size.width / size.height;
    return ratio >= ratioMin && ratio <= ratioMax;
  }

  /// 方屏主播放按钮尺寸
  static double getMainPlayButtonSize(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    if (shortestSide >= 360) return 80;
    if (shortestSide >= 280) return 68;
    return 56;
  }

  /// 方屏副按钮尺寸（上一曲/下一曲）
  static double getSideButtonSize(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    if (shortestSide >= 360) return 60;
    if (shortestSide >= 280) return 52;
    return 44;
  }

  /// 方屏封面尺寸
  static double getCoverSize(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    if (shortestSide >= 360) return 100;
    if (shortestSide >= 280) return 84;
    return 68;
  }

  /// 方屏四边外边距
  static double getOuterPadding(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    if (shortestSide >= 360) return 24;
    if (shortestSide >= 280) return 18;
    return 14;
  }
}
