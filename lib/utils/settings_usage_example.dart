import 'package:bilimusic/utils/settings_manager.dart';

/// 设置管理器使用示例
/// 
/// 这个文件展示了如何在应用程序的其他部分使用SettingsManager
/// 
/// 使用方法:
/// 
/// 1. 导入设置管理器:
///    import 'package:bilimusic/utils/settings_manager.dart';
/// 
/// 2. 获取设置管理器实例:
///    final settings = SettingsManager();
/// 
/// 3. 读取设置:
///    bool notificationsEnabled = settings.notificationsEnabled;
///    String themeMode = settings.themeMode;
/// 
/// 4. 更新设置:
///    settings.setNotificationsEnabled(false);
///    settings.setThemeMode('dark');

class SettingsUsageExample {
  // 获取设置管理器实例
  final SettingsManager _settings = SettingsManager();

  // 示例：检查是否启用了通知
  bool isNotificationsEnabled() {
    return _settings.notificationsEnabled;
  }

  // 示例：切换通知设置
  Future<void> toggleNotifications() async {
    final current = _settings.notificationsEnabled;
    await _settings.setNotificationsEnabled(!current);
  }

  // 示例：获取主题模式
  String getThemeMode() {
    return _settings.themeMode;
  }

  // 示例：设置主题模式
  Future<void> setThemeMode(String mode) async {
    await _settings.setThemeMode(mode);
  }

  // 示例：检查是否自动播放下一首
  bool shouldAutoPlayNext() {
    return _settings.autoPlayNext;
  }

  // 示例：获取主题模式的文本描述
  String getThemeModeDescription() {
    return _settings.getThemeModeText(_settings.themeMode);
  }
}