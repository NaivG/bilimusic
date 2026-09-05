import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:bilimusic/utils/platform_helper.dart';

/// 本机设备身份：UUID + 显示名 + 平台。
///
/// - [id]：首次启动时用 UUID v4 生成，写入 SharedPreferences，永不更换。
/// - [name]：默认从 `device_info_plus` 取设备型号/计算机名，用户可在设置里改。
/// - [platform]：从 [PlatformHelper] 派生的固定字符串。
class DeviceIdentity {
  static const String _prefsId = 'lan_device_id';
  static const String _prefsName = 'lan_device_name';
  static const String _fallbackName = 'BiliMusic Device';

  String _id = '';
  String _name = '';
  String _platform = 'unknown';

  String get id => _id;
  String get name => _name;
  String get platform => _platform;

  /// 从持久化存储加载；缺失字段会自动生成并写回。
  ///
  /// 多次调用幂等。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    var storedId = prefs.getString(_prefsId);
    if (storedId == null || storedId.isEmpty) {
      storedId = const Uuid().v4();
      await prefs.setString(_prefsId, storedId);
    }
    _id = storedId;

    final storedName = prefs.getString(_prefsName);
    if (storedName != null && storedName.isNotEmpty) {
      _name = storedName;
    } else {
      _name = await _defaultDeviceName();
      await prefs.setString(_prefsName, _name);
    }

    _platform = _platformString();
  }

  /// 用户在设置里改设备名。
  Future<void> setName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _name = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsName, trimmed);
  }

  static Future<String> _defaultDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (PlatformHelper.isAndroid) {
        return (await info.androidInfo).model;
      }
      if (PlatformHelper.isIOS) {
        return (await info.iosInfo).name;
      }
      if (PlatformHelper.isWindows) {
        return (await info.windowsInfo).computerName;
      }
      if (PlatformHelper.isMacOS) {
        return (await info.macOsInfo).computerName;
      }
      if (PlatformHelper.isLinux) {
        return (await info.linuxInfo).prettyName;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DeviceIdentity: failed to read device info: $e');
      }
    }
    return _fallbackName;
  }

  static String _platformString() {
    return switch (PlatformHelper.currentPlatform) {
      PlatformType.android => 'android',
      PlatformType.ios => 'ios',
      PlatformType.windows => 'windows',
      PlatformType.macos => 'macos',
      PlatformType.linux => 'linux',
      PlatformType.web => 'web',
    };
  }
}
