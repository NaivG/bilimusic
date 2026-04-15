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

  /// 判断是否为移动端
  static bool isMobile(BuildContext context) {
    return getScreenSize(context) == ScreenSize.mobile;
  }

  /// 判断是否为平板端
  static bool isTablet(BuildContext context) {
    return getScreenSize(context) == ScreenSize.tablet;
  }

  /// 判断是否为桌面端
  static bool isDesktop(BuildContext context) {
    return getScreenSize(context) == ScreenSize.desktop;
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

  /// 根据屏幕尺寸返回不同的卡片高度
  static double responsiveCardHeight(BuildContext context) {
    return responsiveValue<double>(
      context: context,
      mobile: 120.0,
      tablet: 140.0,
      desktop: 160.0,
    );
  }

  /// 根据屏幕尺寸返回不同的字体大小
  static double responsiveFontSize({
    required BuildContext context,
    required double mobile,
    required double tablet,
    required double desktop,
  }) {
    return responsiveValue<double>(
      context: context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}

/// 响应式布局组件
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1200) {
          return desktop;
        } else if (constraints.maxWidth >= 600) {
          return tablet;
        } else {
          return mobile;
        }
      },
    );
  }
}

/// 自适应容器组件
class AdaptiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? maxWidth;

  const AdaptiveContainer({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? _getMaxWidth(context),
        ),
        padding: padding ?? _getPadding(context),
        child: child,
      ),
    );
  }

  double _getMaxWidth(BuildContext context) {
    return ResponsiveHelper.responsiveValue<double>(
      context: context,
      mobile: double.infinity,
      tablet: 800,
      desktop: 1200,
    );
  }

  EdgeInsets _getPadding(BuildContext context) {
    final spacing = ResponsiveHelper.responsiveSpacing(context);
    return EdgeInsets.all(spacing);
  }
}

/// 响应式断点定义
class Breakpoints {
  /// 移动端最大宽度
  static const double mobileMax = 599;

  /// 平板端最小宽度
  static const double tabletMin = 600;

  /// 平板端最大宽度
  static const double tabletMax = 1199;

  /// 桌面端最小宽度
  static const double desktopMin = 1200;

  /// 检查当前宽度是否在移动端范围内
  static bool isMobileWidth(double width) {
    return width <= mobileMax;
  }

  /// 检查当前宽度是否在平板端范围内
  static bool isTabletWidth(double width) {
    return width >= tabletMin && width <= tabletMax;
  }

  /// 检查当前宽度是否在桌面端范围内
  static bool isDesktopWidth(double width) {
    return width >= desktopMin;
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

  /// 获取横屏封面尺寸
  static double getCoverSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 340;
    if (width >= largeTabletMin) return 300;
    return 260;
  }

  /// 获取横屏控制条高度
  static double getControlsBarHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 140; // 这里反直觉的是在桌面端需要控制按钮小一些
    return 160; // 移动横屏端需要控制按钮大一些
  }

  /// 获取横屏歌词当前行字号
  static double getCurrentLyricFontSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 26;
    if (width >= largeTabletMin) return 24;
    return 22;
  }

  /// 获取横屏歌词其他行字号
  static double getOtherLyricFontSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= largeTabletMin) return 18;
    return 16;
  }

  /// 获取横屏主播放按钮尺寸
  static double getMainPlayButtonSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 68;
    if (width >= largeTabletMin) return 64;
    return 60;
  }

  /// 获取横屏左侧区域比例
  static double getLeftSectionRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 0.42;
    if (width >= largeTabletMin) return 0.40;
    return 0.38;
  }

  /// 获取横屏边距
  static double getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopMin) return 48;
    if (width >= largeTabletMin) return 32;
    return 24;
  }
}
