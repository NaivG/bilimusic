import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:bilimusic/shared/utils/platform_helper.dart';

/// iOS 原生标签栏（`ios/Runner/NativeTabBarHost.swift`）的桥。
///
/// iPhone + iOS 26 以上时，窗口根是系统 `UITabBarController`，由它绘制
/// Liquid Glass 标签栏，代替竖屏外壳的 Flutter Dock：普通 iPhone 在底部，
/// iPhone Duo 合上时在竖状态栏里。其他平台 / 设备上 [isActive] 为 false，
/// 外壳照常绘制 Flutter 导航。
///
/// 只有一个原生标签栏，这里用静态状态，并对重复的调用去重。
abstract final class NativeTabBar {
  static const MethodChannel _channel = MethodChannel(
    'bilimusic/native_tab_bar',
  );

  static bool _isActive = false;

  /// 原生侧是否接管了标签栏。
  static bool get isActive => _isActive;

  static ValueChanged<int>? _onSelect;

  static bool? _lastHidden;
  static int? _lastIndex;
  static List<String>? _lastTitles;
  static int? _lastTint;

  /// 询问原生侧是否托管标签栏。在 runApp 之前调用，首帧就用对的布局。
  static Future<void> initialize() async {
    if (!PlatformHelper.isIOS) return;
    try {
      _isActive = await _channel.invokeMethod<bool>('isActive') ?? false;
    } on MissingPluginException {
      _isActive = false;
    } on PlatformException catch (e) {
      debugPrint('[NativeTabBar] 不可用：${e.message}');
      _isActive = false;
    }
    if (!_isActive) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'select' && call.arguments is int) {
        _lastIndex = call.arguments as int;
        _onSelect?.call(_lastIndex!);
      }
    });
  }

  /// 用户在原生标签栏里点选的标签。
  static set onSelect(ValueChanged<int>? callback) => _onSelect = callback;

  static void setSelectedIndex(int index) {
    if (!_isActive || _lastIndex == index) return;
    _lastIndex = index;
    _invoke('setSelectedIndex', index);
  }

  static void setHidden(bool hidden) {
    if (!_isActive || _lastHidden == hidden) return;
    _lastHidden = hidden;
    _invoke('setTabBarHidden', hidden);
  }

  static void setTitles(List<String> titles) {
    if (!_isActive || listEquals(_lastTitles, titles)) return;
    _lastTitles = titles;
    _invoke('setTitles', titles);
  }

  /// 选中项的颜色跟随主题强调色。
  static void setTintColor(Color color) {
    final argb = color.toARGB32();
    if (!_isActive || _lastTint == argb) return;
    _lastTint = argb;
    _invoke('setTintColor', argb);
  }

  static Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint('[NativeTabBar] $method 失败：${e.message}');
    }
  }
}
