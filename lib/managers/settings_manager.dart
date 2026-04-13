import 'package:shared_preferences/shared_preferences.dart';

/// 设置管理器
class SettingsManager {
  // 设置键名常量
  static const String KEY_NOTIFICATIONS_ENABLED = 'notifications_enabled';
  static const String KEY_DOWNLOAD_QUALITY_HIGH = 'download_quality_high';
  static const String KEY_THEME_MODE = 'theme_mode';
  static const String KEY_AUTO_PLAY_NEXT = 'auto_play_next';
  static const String KEY_SHOW_LYRICS = 'show_lyrics';
  static const String KEY_TABLET_MODE = 'tablet_mode'; // 平板模式设置项
  static const String KEY_FLUID_BACKGROUND = 'fluid_background';
  static const String KEY_BLUR_EFFECT = 'blur_effect'; // 新增毛玻璃取色效果设置项
  static const String KEY_AUDIO_OUTPUT_MODE = 'audio_output_mode'; // 音频输出模式设置项
  static const String KEY_VERSION_CODE = 'version_code';
  static const String KEY_PC_MODE = 'pc_mode';

  // Crossfade相关设置键名
  static const String KEY_CROSSFADE_ENABLED = 'crossfade_enabled';
  static const String KEY_CROSSFADE_DURATION = 'crossfade_duration';
  static const String KEY_PRELOAD_SECONDS = 'preload_seconds';

  // 默认值
  static const bool DEFAULT_NOTIFICATIONS_ENABLED = true;
  static const bool DEFAULT_DOWNLOAD_QUALITY_HIGH = true;
  static const String DEFAULT_THEME_MODE = 'system';
  static const bool DEFAULT_AUTO_PLAY_NEXT = true;
  static const bool DEFAULT_SHOW_LYRICS = true;
  static const String DEFAULT_TABLET_MODE = 'auto';
  static const bool DEFAULT_FLUID_BACKGROUND = true;
  static const bool DEFAULT_BLUR_EFFECT = true; // 新增默认值
  static const String DEFAULT_AUDIO_OUTPUT_MODE =
      'audiotrack'; // 默认使用AudioTrack
  static const int DEFAULT_VERSION_CODE = 26;
  static const bool DEFAULT_PC_MODE = false;

  // Crossfade相关默认值
  static const bool DEFAULT_CROSSFADE_ENABLED = false; // 默认关闭
  static const int DEFAULT_CROSSFADE_DURATION = 3000; // 3秒
  static const int DEFAULT_PRELOAD_SECONDS = 10; // 剩10秒时预加载

  // 单例实例
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  // 设置值的内存缓存，避免频繁读取磁盘
  Map<String, dynamic> _cache = {};

  /// 初始化设置管理器
  Future<void> init() async {
    await _loadAllSettings();
  }

  /// 加载所有设置到缓存
  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _cache[KEY_NOTIFICATIONS_ENABLED] =
        prefs.getBool(KEY_NOTIFICATIONS_ENABLED) ??
        DEFAULT_NOTIFICATIONS_ENABLED;
    _cache[KEY_DOWNLOAD_QUALITY_HIGH] =
        prefs.getBool(KEY_DOWNLOAD_QUALITY_HIGH) ??
        DEFAULT_DOWNLOAD_QUALITY_HIGH;
    _cache[KEY_THEME_MODE] =
        prefs.getString(KEY_THEME_MODE) ?? DEFAULT_THEME_MODE;
    _cache[KEY_AUTO_PLAY_NEXT] =
        prefs.getBool(KEY_AUTO_PLAY_NEXT) ?? DEFAULT_AUTO_PLAY_NEXT;
    _cache[KEY_SHOW_LYRICS] =
        prefs.getBool(KEY_SHOW_LYRICS) ?? DEFAULT_SHOW_LYRICS;
    _cache[KEY_TABLET_MODE] =
        prefs.getString(KEY_TABLET_MODE) ?? DEFAULT_TABLET_MODE;
    _cache[KEY_FLUID_BACKGROUND] =
        prefs.getBool(KEY_FLUID_BACKGROUND) ?? DEFAULT_FLUID_BACKGROUND;
    _cache[KEY_BLUR_EFFECT] =
        prefs.getBool(KEY_BLUR_EFFECT) ?? DEFAULT_BLUR_EFFECT; // 新增加载
    _cache[KEY_AUDIO_OUTPUT_MODE] =
        prefs.getString(KEY_AUDIO_OUTPUT_MODE) ??
        DEFAULT_AUDIO_OUTPUT_MODE; // 加载音频输出模式
    _cache[KEY_VERSION_CODE] = DEFAULT_VERSION_CODE;
    _cache[KEY_PC_MODE] = prefs.getBool(KEY_PC_MODE) ?? DEFAULT_PC_MODE;

    // 加载Crossfade相关设置
    _cache[KEY_CROSSFADE_ENABLED] =
        prefs.getBool(KEY_CROSSFADE_ENABLED) ?? DEFAULT_CROSSFADE_ENABLED;
    _cache[KEY_CROSSFADE_DURATION] =
        prefs.getInt(KEY_CROSSFADE_DURATION) ?? DEFAULT_CROSSFADE_DURATION;
    _cache[KEY_PRELOAD_SECONDS] =
        prefs.getInt(KEY_PRELOAD_SECONDS) ?? DEFAULT_PRELOAD_SECONDS;
  }

  /// 获取通知设置
  bool get notificationsEnabled =>
      _cache[KEY_NOTIFICATIONS_ENABLED] ?? DEFAULT_NOTIFICATIONS_ENABLED;

  /// 设置通知设置
  Future<void> setNotificationsEnabled(bool value) async {
    await _saveSetting(KEY_NOTIFICATIONS_ENABLED, value);
    _cache[KEY_NOTIFICATIONS_ENABLED] = value;
  }

  /// 获取下载音质设置
  bool get downloadQualityHigh =>
      _cache[KEY_DOWNLOAD_QUALITY_HIGH] ?? DEFAULT_DOWNLOAD_QUALITY_HIGH;

  /// 设置下载音质设置
  Future<void> setDownloadQualityHigh(bool value) async {
    await _saveSetting(KEY_DOWNLOAD_QUALITY_HIGH, value);
    _cache[KEY_DOWNLOAD_QUALITY_HIGH] = value;
  }

  /// 获取主题模式设置
  String get themeMode => _cache[KEY_THEME_MODE] ?? DEFAULT_THEME_MODE;

  /// 设置主题模式
  Future<void> setThemeMode(String value) async {
    await _saveSetting(KEY_THEME_MODE, value);
    _cache[KEY_THEME_MODE] = value;
  }

  /// 获取自动播放下一首设置
  bool get autoPlayNext => _cache[KEY_AUTO_PLAY_NEXT] ?? DEFAULT_AUTO_PLAY_NEXT;

  /// 设置自动播放下一首
  Future<void> setAutoPlayNext(bool value) async {
    await _saveSetting(KEY_AUTO_PLAY_NEXT, value);
    _cache[KEY_AUTO_PLAY_NEXT] = value;
  }

  /// 获取显示歌词设置
  bool get showLyrics => _cache[KEY_SHOW_LYRICS] ?? DEFAULT_SHOW_LYRICS;

  /// 设置显示歌词
  Future<void> setShowLyrics(bool value) async {
    await _saveSetting(KEY_SHOW_LYRICS, value);
    _cache[KEY_SHOW_LYRICS] = value;
  }

  /// 获取平板模式设置
  String get tabletMode => _cache[KEY_TABLET_MODE] ?? DEFAULT_TABLET_MODE;

  /// 设置平板模式
  Future<void> setTabletMode(String value) async {
    await _saveSetting(KEY_TABLET_MODE, value);
    _cache[KEY_TABLET_MODE] = value;
  }

  /// 获取流体背景设置
  bool get fluidBackground =>
      _cache[KEY_FLUID_BACKGROUND] ?? DEFAULT_FLUID_BACKGROUND;

  /// 设置流体背景
  Future<void> setFluidBackground(bool value) async {
    await _saveSetting(KEY_FLUID_BACKGROUND, value);
    _cache[KEY_FLUID_BACKGROUND] = value;
  }

  /// 获取毛玻璃取色效果设置
  bool get blurEffect => _cache[KEY_BLUR_EFFECT] ?? DEFAULT_BLUR_EFFECT;

  /// 设置毛玻璃取色效果
  Future<void> setBlurEffect(bool value) async {
    await _saveSetting(KEY_BLUR_EFFECT, value);
    _cache[KEY_BLUR_EFFECT] = value;
  }

  /// 获取音频输出模式设置
  String get audioOutputMode =>
      _cache[KEY_AUDIO_OUTPUT_MODE] ?? DEFAULT_AUDIO_OUTPUT_MODE;

  /// 设置音频输出模式
  Future<void> setAudioOutputMode(String value) async {
    await _saveSetting(KEY_AUDIO_OUTPUT_MODE, value);
    _cache[KEY_AUDIO_OUTPUT_MODE] = value;
  }

  /// 通用设置保存方法
  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();

    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  // ============ Crossfade相关设置 ============

  /// 获取是否启用Crossfade
  bool get crossfadeEnabled =>
      _cache[KEY_CROSSFADE_ENABLED] ?? DEFAULT_CROSSFADE_ENABLED;

  /// 设置是否启用Crossfade
  Future<void> setCrossfadeEnabled(bool value) async {
    await _saveSetting(KEY_CROSSFADE_ENABLED, value);
    _cache[KEY_CROSSFADE_ENABLED] = value;
  }

  /// 获取Crossfade时长(毫秒)
  int get crossfadeDuration =>
      _cache[KEY_CROSSFADE_DURATION] ?? DEFAULT_CROSSFADE_DURATION;

  /// 设置Crossfade时长(毫秒),范围1-10秒
  Future<void> setCrossfadeDuration(int value) async {
    // 限制范围在1000-10000毫秒之间
    final clampedValue = value.clamp(1000, 10000);

    // 确保淡入淡出时长不超过提前加载时间（转换为秒比较）
    final preloadSecondsValue = preloadSeconds;
    final crossfadeSeconds = (clampedValue / 1000).ceil();

    if (crossfadeSeconds > preloadSecondsValue) {
      // 如果淡入淡出时长超过提前加载时间，则自动调整提前加载时间
      await _saveSetting(KEY_PRELOAD_SECONDS, crossfadeSeconds);
      _cache[KEY_PRELOAD_SECONDS] = crossfadeSeconds;
    }

    await _saveSetting(KEY_CROSSFADE_DURATION, clampedValue);
    _cache[KEY_CROSSFADE_DURATION] = clampedValue;
  }

  /// 获取预加载触发时间(秒)
  int get preloadSeconds =>
      _cache[KEY_PRELOAD_SECONDS] ?? DEFAULT_PRELOAD_SECONDS;

  /// 设置预加载触发时间(秒),范围5-30秒
  Future<void> setPreloadSeconds(int value) async {
    // 限制范围在5-30秒之间
    final clampedValue = value.clamp(5, 30);

    // 确保提前加载时间不小于淡入淡出时长（转换为秒比较）
    final crossfadeDurationSeconds = (crossfadeDuration / 1000).ceil();
    final finalValue = clampedValue < crossfadeDurationSeconds
        ? crossfadeDurationSeconds
        : clampedValue;

    await _saveSetting(KEY_PRELOAD_SECONDS, finalValue);
    _cache[KEY_PRELOAD_SECONDS] = finalValue;
  }

  /// 获取主题模式的文本描述
  String getThemeModeText(String mode) {
    switch (mode) {
      case 'system':
        return '跟随系统';
      case 'light':
        return '浅色';
      case 'dark':
        return '深色';
      default:
        return '跟随系统';
    }
  }

  /// 获取平板模式的文本描述
  String getTabletModeText(String mode) {
    switch (mode) {
      case 'auto':
        return '自动';
      case 'on':
        return '强制打开';
      case 'off':
        return '强制关闭';
      default:
        return '自动';
    }
  }

  /// 获取音频输出模式的文本描述
  String getAudioOutputModeText(String mode) {
    switch (mode) {
      case 'aaudio':
        return 'AAudio (推荐)';
      case 'audiotrack':
        return 'AudioTrack';
      default:
        return 'AudioTrack';
    }
  }

  bool get pcMode => _cache[KEY_PC_MODE] ?? DEFAULT_PC_MODE;

  Future<void> setPcMode(bool value) async {
    await _saveSetting(KEY_PC_MODE, value);
    _cache[KEY_PC_MODE] = value;
  }
}
