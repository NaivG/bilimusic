import 'dart:io';
import 'package:flutter/foundation.dart';

/// 平台类型枚举
enum PlatformType {
  /// Web平台
  web,

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
}

/// 平台辅助工具类
class PlatformHelper {
  /// 获取当前平台类型
  static PlatformType get currentPlatform {
    if (kIsWeb) return PlatformType.web;
    if (Platform.isAndroid) return PlatformType.android;
    if (Platform.isIOS) return PlatformType.ios;
    if (Platform.isWindows) return PlatformType.windows;
    if (Platform.isLinux) return PlatformType.linux;
    if (Platform.isMacOS) return PlatformType.macos;
    return PlatformType.web; // 未知的非Web平台默认为Web
  }

  /// 判断是否为Web平台
  static bool get isWeb => kIsWeb;

  /// 判断是否为移动平台（Android或iOS）
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 判断是否为桌面平台（Windows、Linux或macOS）
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 判断是否为Android平台
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 判断是否为iOS平台
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// 判断是否为Windows平台
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 判断是否为Linux平台
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// 判断是否为macOS平台
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// 根据平台返回不同的值
  static T platformValue<T>({
    required T web,
    required T android,
    required T ios,
    required T windows,
    required T linux,
    required T macos,
  }) {
    switch (currentPlatform) {
      case PlatformType.web:
        return web;
      case PlatformType.android:
        return android;
      case PlatformType.ios:
        return ios;
      case PlatformType.windows:
        return windows;
      case PlatformType.linux:
        return linux;
      case PlatformType.macos:
        return macos;
    }
  }

  /// 移动端和桌面端的值
  static T deviceValue<T>({required T mobile, required T desktop, T? web}) {
    if (kIsWeb) return web ?? desktop;
    if (isMobile) return mobile;
    return desktop;
  }

  /// 获取平台名称
  static String get platformName {
    return platformValue<String>(
      web: 'Web',
      android: 'Android',
      ios: 'iOS',
      windows: 'Windows',
      linux: 'Linux',
      macos: 'macOS',
    );
  }

  /// 检查是否需要窗口管理（桌面平台）
  static bool get needsWindowManagement => isDesktop;

  /// 检查是否需要移动端特定功能
  static bool get needsMobileFeatures => isMobile;

  /// 检查是否需要Web特定功能
  static bool get needsWebFeatures => kIsWeb;

  /// 获取平台特定的默认设置
  static Map<String, dynamic> get platformDefaults {
    return platformValue<Map<String, dynamic>>(
      web: {
        'audioOutputMode': 'default',
        'notificationsEnabled': false,
        'pcMode': true,
      },
      android: {
        'audioOutputMode': 'aaudio',
        'notificationsEnabled': true,
        'pcMode': false,
      },
      ios: {
        'audioOutputMode': 'default',
        'notificationsEnabled': true,
        'pcMode': false,
      },
      windows: {
        'audioOutputMode': 'default',
        'notificationsEnabled': true,
        'pcMode': true,
      },
      linux: {
        'audioOutputMode': 'default',
        'notificationsEnabled': true,
        'pcMode': true,
      },
      macos: {
        'audioOutputMode': 'default',
        'notificationsEnabled': true,
        'pcMode': true,
      },
    );
  }
}
