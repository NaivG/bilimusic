import 'dart:io';

/// 平台类型枚举
enum PlatformType {
  /// Android平台
  android,

  /// iOS平台
  ios,

  /// Windows平台
  windows,

  /// Linux平台
  linux,

  /// macOS平台
  macos,

  /// 未知平台（兜底值）。
  unknown,
}

/// 平台辅助工具类
class PlatformHelper {
  /// 获取当前平台类型
  static PlatformType get currentPlatform {
    if (Platform.isAndroid) return PlatformType.android;
    if (Platform.isIOS) return PlatformType.ios;
    if (Platform.isWindows) return PlatformType.windows;
    if (Platform.isLinux) return PlatformType.linux;
    if (Platform.isMacOS) return PlatformType.macos;
    return PlatformType.unknown; // 未识别平台的兜底
  }

  /// 判断是否为移动平台（Android或iOS）
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// 判断是否为桌面平台（Windows、Linux或macOS）
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 判断是否为Android平台
  static bool get isAndroid => Platform.isAndroid;

  /// 判断是否为iOS平台
  static bool get isIOS => Platform.isIOS;

  /// 判断是否为Windows平台
  static bool get isWindows => Platform.isWindows;

  /// 判断是否为Linux平台
  static bool get isLinux => Platform.isLinux;

  /// 判断是否为macOS平台
  static bool get isMacOS => Platform.isMacOS;
}
