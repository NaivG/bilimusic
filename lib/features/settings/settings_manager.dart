// ignore_for_file: constant_identifier_names

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/features/roam/models/roam_style.dart';
import 'package:bilimusic/features/settings/logic/audio_output_options.dart';
import 'package:bilimusic/shared/utils/title_meta_filter.dart';

/// 设置管理器
class SettingsManager extends ChangeNotifier {
  // 设置键名常量
  static const String KEY_NOTIFICATIONS_ENABLED = 'notifications_enabled';
  static const String KEY_APPEARANCE = 'appearance';
  static const String KEY_THEME = 'theme';
  static const String KEY_AUTO_PLAY_NEXT = 'auto_play_next';
  static const String KEY_SHOW_LYRICS = 'show_lyrics';
  static const String KEY_TABLET_MODE = 'tablet_mode'; // 平板模式设置项
  static const String KEY_FLUID_BACKGROUND = 'fluid_background';
  static const String KEY_BLUR_EFFECT = 'blur_effect'; // 新增毛玻璃取色效果设置项
  static const String KEY_AUDIO_QUALITY = 'audio_quality'; // 播放音质设置项
  static const String KEY_VERSION_CODE = 'version_code';

  // 音频输出设置键名（音频输出页的四项 + 一次性免责闸门）。
  // 全是扁平标量，所以进 SettingsManager 而不是像 DSP 效果包那样单独开
  // 一个服务——见 `AudioEffectsService.prefsKey` 的「嵌套 JSON、与扁平
  // 设置不同源」那段注释，我们正好在它划的界线另一侧。
  static const String KEY_AUDIO_OUTPUT_DISCLAIMER =
      'audio_output_disclaimer_accepted';
  static const String KEY_AUDIO_DELAY_MS = 'audio_delay_ms';
  static const String KEY_AUDIO_EXCLUSIVE = 'audio_exclusive';
  static const String KEY_AUDIO_SAMPLERATE = 'audio_samplerate';
  static const String KEY_AUDIO_DEVICE = 'audio_device';

  // Crossfade相关设置键名
  static const String KEY_CROSSFADE_ENABLED = 'crossfade_enabled';
  static const String KEY_CROSSFADE_DURATION = 'crossfade_duration';
  static const String KEY_CROSSFADE_AUTO = 'crossfade_auto';
  static const String KEY_PRELOAD_SECONDS = 'preload_seconds';

  // 漫游模式设置键名
  static const String KEY_ROAM_STYLE = 'roam_style';
  static const String KEY_ROAM_REFILL_THRESHOLD = 'roam_refill_threshold';

  // 局域网同步设置键名
  static const String KEY_LAN_SYNC_MODE = 'lan_sync_mode';
  static const String KEY_LAN_SYNC_DEVICE_NAME = 'lan_sync_device_name';

  // 窗口行为设置键名
  static const String KEY_CLOSE_BEHAVIOR = 'close_behavior';

  // 标题元数据过滤（实验性）设置键名
  static const String KEY_TITLE_META_FILTER = 'title_meta_filter';

  // 默认值
  static const bool DEFAULT_NOTIFICATIONS_ENABLED = true;
  static const String DEFAULT_APPEARANCE = 'system';
  static const String DEFAULT_THEME = 'lucent';
  static const bool DEFAULT_AUTO_PLAY_NEXT = true;
  static const bool DEFAULT_SHOW_LYRICS = true;
  static const String DEFAULT_TABLET_MODE = 'auto';
  static const bool DEFAULT_FLUID_BACKGROUND = true;
  static const bool DEFAULT_BLUR_EFFECT = true;
  static const String DEFAULT_AUDIO_QUALITY = '30280'; // 默认 192K 高品
  static const int DEFAULT_VERSION_CODE = 80;
  static const bool DEFAULT_PC_MODE = false;

  // 音频输出默认值：延迟 0ms、不开独占、采样率跟随源、设备跟随系统。
  static const bool DEFAULT_AUDIO_OUTPUT_DISCLAIMER = false;
  static const int DEFAULT_AUDIO_DELAY_MS = 0;
  static const bool DEFAULT_AUDIO_EXCLUSIVE = false;
  static const int DEFAULT_AUDIO_SAMPLERATE = 0; // 0 = 自动
  static const String DEFAULT_AUDIO_DEVICE = ''; // 空串 = mpv auto

  // Crossfade相关默认值
  static const bool DEFAULT_CROSSFADE_ENABLED = false; // 默认关闭
  static const int DEFAULT_CROSSFADE_DURATION = 3000; // 3秒
  static const bool DEFAULT_CROSSFADE_AUTO = false; // 自动过渡默认关闭
  static const int DEFAULT_PRELOAD_SECONDS = 10; // 剩10秒时预加载

  // 漫游模式默认值
  static const RoamStyle DEFAULT_ROAM_STYLE = RoamStyle.balanced;
  static const int DEFAULT_ROAM_REFILL_THRESHOLD = 2;

  // 局域网同步默认值
  static const String DEFAULT_LAN_SYNC_MODE = 'off';
  static const String DEFAULT_LAN_SYNC_DEVICE_NAME = '';

  // 关闭行为取值
  static const String CLOSE_BEHAVIOR_PROMPT = 'prompt'; // 弹出提示
  static const String CLOSE_BEHAVIOR_MINIMIZE_TRAY = 'minimize_tray'; // 最小化至托盘
  static const String CLOSE_BEHAVIOR_EXIT = 'exit'; // 直接退出

  // 窗口行为默认值：关闭时弹窗询问
  static const String DEFAULT_CLOSE_BEHAVIOR = CLOSE_BEHAVIOR_PROMPT;

  // 标题元数据过滤默认值：实验性功能，默认关闭
  static const bool DEFAULT_TITLE_META_FILTER = false;

  // 单例实例
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  // 设置值的内存缓存，避免频繁读取磁盘
  Map<String, dynamic> _cache = {};

  /// 初始化设置管理器
  Future<void> init() async {
    await _migrateLegacyKeys();
    await _loadAllSettings();
  }

  /// 一次性迁移:旧的 `theme_mode`/`theme_color` 键值迁到 `appearance`/`theme`。
  /// 仅在新键未写入时执行,避免覆盖用户新设置。
  Future<void> _migrateLegacyKeys() async {
    const legacyAppearance = 'theme_mode';
    const legacyTheme = 'theme_color';
    final prefs = await SharedPreferences.getInstance();
    var migrated = false;
    if (!prefs.containsKey(KEY_APPEARANCE) &&
        prefs.containsKey(legacyAppearance)) {
      final v = prefs.getString(legacyAppearance);
      if (v != null) {
        await prefs.setString(KEY_APPEARANCE, v);
        migrated = true;
      }
      await prefs.remove(legacyAppearance);
    }
    if (!prefs.containsKey(KEY_THEME) && prefs.containsKey(legacyTheme)) {
      final v = prefs.getString(legacyTheme);
      if (v != null) {
        await prefs.setString(KEY_THEME, v);
        migrated = true;
      }
      await prefs.remove(legacyTheme);
    }
    if (migrated) {
      debugPrint('SettingsManager: migrated legacy theme keys');
    }
  }

  /// 加载所有设置到缓存
  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _cache[KEY_NOTIFICATIONS_ENABLED] =
        prefs.getBool(KEY_NOTIFICATIONS_ENABLED) ??
        DEFAULT_NOTIFICATIONS_ENABLED;
    _cache[KEY_APPEARANCE] =
        prefs.getString(KEY_APPEARANCE) ?? DEFAULT_APPEARANCE;
    _cache[KEY_THEME] = prefs.getString(KEY_THEME) ?? DEFAULT_THEME;

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
    _cache[KEY_AUDIO_QUALITY] =
        prefs.getString(KEY_AUDIO_QUALITY) ?? DEFAULT_AUDIO_QUALITY; // 加载播放音质
    _cache[KEY_VERSION_CODE] = DEFAULT_VERSION_CODE;

    // 加载音频输出设置
    _cache[KEY_AUDIO_OUTPUT_DISCLAIMER] =
        prefs.getBool(KEY_AUDIO_OUTPUT_DISCLAIMER) ??
        DEFAULT_AUDIO_OUTPUT_DISCLAIMER;
    _cache[KEY_AUDIO_DELAY_MS] =
        prefs.getInt(KEY_AUDIO_DELAY_MS) ?? DEFAULT_AUDIO_DELAY_MS;
    _cache[KEY_AUDIO_EXCLUSIVE] =
        prefs.getBool(KEY_AUDIO_EXCLUSIVE) ?? DEFAULT_AUDIO_EXCLUSIVE;
    _cache[KEY_AUDIO_SAMPLERATE] =
        prefs.getInt(KEY_AUDIO_SAMPLERATE) ?? DEFAULT_AUDIO_SAMPLERATE;
    _cache[KEY_AUDIO_DEVICE] =
        prefs.getString(KEY_AUDIO_DEVICE) ?? DEFAULT_AUDIO_DEVICE;

    // 加载Crossfade相关设置
    _cache[KEY_CROSSFADE_ENABLED] =
        prefs.getBool(KEY_CROSSFADE_ENABLED) ?? DEFAULT_CROSSFADE_ENABLED;
    _cache[KEY_CROSSFADE_DURATION] =
        prefs.getInt(KEY_CROSSFADE_DURATION) ?? DEFAULT_CROSSFADE_DURATION;
    _cache[KEY_CROSSFADE_AUTO] =
        prefs.getBool(KEY_CROSSFADE_AUTO) ?? DEFAULT_CROSSFADE_AUTO;
    _cache[KEY_PRELOAD_SECONDS] =
        prefs.getInt(KEY_PRELOAD_SECONDS) ?? DEFAULT_PRELOAD_SECONDS;

    // 加载漫游模式设置
    _cache[KEY_ROAM_STYLE] =
        prefs.getString(KEY_ROAM_STYLE) ?? DEFAULT_ROAM_STYLE.name;
    _cache[KEY_ROAM_REFILL_THRESHOLD] =
        prefs.getInt(KEY_ROAM_REFILL_THRESHOLD) ??
        DEFAULT_ROAM_REFILL_THRESHOLD;

    // 加载局域网同步设置
    _cache[KEY_LAN_SYNC_MODE] =
        prefs.getString(KEY_LAN_SYNC_MODE) ?? DEFAULT_LAN_SYNC_MODE;
    _cache[KEY_LAN_SYNC_DEVICE_NAME] =
        prefs.getString(KEY_LAN_SYNC_DEVICE_NAME) ??
        DEFAULT_LAN_SYNC_DEVICE_NAME;

    // 加载窗口行为设置
    _cache[KEY_CLOSE_BEHAVIOR] =
        prefs.getString(KEY_CLOSE_BEHAVIOR) ?? DEFAULT_CLOSE_BEHAVIOR;

    // 加载标题元数据过滤（实验性），并同步静态开关：
    // API 解析在 domain 层（fromArchiveJson / fromViewApi 等），
    // 那里读不到 SettingsManager，只能读 TitleMetaFilter.enabled。
    final titleMetaFilter =
        prefs.getBool(KEY_TITLE_META_FILTER) ?? DEFAULT_TITLE_META_FILTER;
    _cache[KEY_TITLE_META_FILTER] = titleMetaFilter;
    TitleMetaFilter.enabled = titleMetaFilter;
  }

  /// 获取通知设置
  bool get notificationsEnabled =>
      _cache[KEY_NOTIFICATIONS_ENABLED] ?? DEFAULT_NOTIFICATIONS_ENABLED;

  /// 设置通知设置
  Future<void> setNotificationsEnabled(bool value) async {
    await _saveSetting(KEY_NOTIFICATIONS_ENABLED, value);
    _cache[KEY_NOTIFICATIONS_ENABLED] = value;
  }

  /// 获取外观设置 (system / light / dark)
  String get appearance => _cache[KEY_APPEARANCE] ?? DEFAULT_APPEARANCE;

  /// 设置外观
  Future<void> setAppearance(String value) async {
    await _saveSetting(KEY_APPEARANCE, value);
    _cache[KEY_APPEARANCE] = value;
  }

  /// 获取主题设置 (lucent / nocturne / verdant)
  String get theme => _cache[KEY_THEME] ?? DEFAULT_THEME;

  /// 设置主题
  Future<void> setTheme(String value) async {
    await _saveSetting(KEY_THEME, value);
    _cache[KEY_THEME] = value;
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

  /// 获取播放音质设置 (30216=64K / 30232=132K / 30280=192K / 30250=杜比 / 30251=Hi-Res)
  String get audioQuality => _cache[KEY_AUDIO_QUALITY] ?? DEFAULT_AUDIO_QUALITY;

  /// 设置播放音质
  Future<void> setAudioQuality(String value) async {
    await _saveSetting(KEY_AUDIO_QUALITY, value);
    _cache[KEY_AUDIO_QUALITY] = value;
  }

  /// 通用设置保存方法
  Future<void> _saveSetting(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      }
      _cache[key] = value;
    } catch (e) {
      // 处理保存设置时的错误，例如日志记录
      debugPrint('Error saving setting $key: $e');
    }
    notifyListeners(); // 通知监听器设置已更改
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

  /// 获取是否启用自动Crossfade（过渡位置与时长按曲目时长推导）
  bool get crossfadeAuto =>
      _cache[KEY_CROSSFADE_AUTO] ?? DEFAULT_CROSSFADE_AUTO;

  /// 设置是否启用自动Crossfade
  Future<void> setCrossfadeAuto(bool value) async {
    await _saveSetting(KEY_CROSSFADE_AUTO, value);
    _cache[KEY_CROSSFADE_AUTO] = value;
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

  // ============ 漫游模式相关设置 ============

  /// 获取漫游风格档位，默认 [RoamStyle.balanced]。
  RoamStyle get roamStyle {
    final name = _cache[KEY_ROAM_STYLE] as String?;
    if (name == null) return DEFAULT_ROAM_STYLE;
    return RoamStyle.values.firstWhere(
      (e) => e.name == name,
      orElse: () => DEFAULT_ROAM_STYLE,
    );
  }

  /// 设置漫游风格档位（持久化）。
  Future<void> setRoamStyle(RoamStyle value) async {
    await _saveSetting(KEY_ROAM_STYLE, value.name);
  }

  /// 获取队列剩余触发 fetch 的阈值（默认 2，范围 1~5）。
  int get roamRefillThreshold =>
      _cache[KEY_ROAM_REFILL_THRESHOLD] ?? DEFAULT_ROAM_REFILL_THRESHOLD;

  /// 设置阈值并夹到 1~5。
  Future<void> setRoamRefillThreshold(int value) async {
    final clamped = value.clamp(1, 5);
    await _saveSetting(KEY_ROAM_REFILL_THRESHOLD, clamped);
  }

  // ============ 局域网同步相关设置 ============

  /// 局域网同步模式：`off` / `private` / `public`。
  String get lanSyncMode => _cache[KEY_LAN_SYNC_MODE] ?? DEFAULT_LAN_SYNC_MODE;

  Future<void> setLanSyncMode(String value) async {
    await _saveSetting(KEY_LAN_SYNC_MODE, value);
  }

  /// 用户自定义的设备名。空字符串表示沿用 DeviceIdentity 的默认值。
  String get lanSyncDeviceName =>
      _cache[KEY_LAN_SYNC_DEVICE_NAME] ?? DEFAULT_LAN_SYNC_DEVICE_NAME;

  Future<void> setLanSyncDeviceName(String value) async {
    await _saveSetting(KEY_LAN_SYNC_DEVICE_NAME, value);
  }

  // ============ 窗口行为相关设置 ============

  /// 获取窗口关闭行为
  /// (prompt=弹出提示 / minimize_tray=最小化至托盘 / exit=直接退出)
  String get closeBehavior =>
      _cache[KEY_CLOSE_BEHAVIOR] ?? DEFAULT_CLOSE_BEHAVIOR;

  /// 设置窗口关闭行为
  Future<void> setCloseBehavior(String value) async {
    await _saveSetting(KEY_CLOSE_BEHAVIOR, value);
  }

  /// 获取关闭行为的文本描述
  String getCloseBehaviorText(String mode) {
    switch (mode) {
      case CLOSE_BEHAVIOR_MINIMIZE_TRAY:
        return '最小化至托盘';
      case CLOSE_BEHAVIOR_EXIT:
        return '直接退出';
      case CLOSE_BEHAVIOR_PROMPT:
      default:
        return '弹出提示';
    }
  }

  // ============ 标题元数据过滤（实验性） ============

  /// 是否启用标题元数据过滤（实验性，默认关闭）。
  bool get titleMetaFilterEnabled =>
      _cache[KEY_TITLE_META_FILTER] ?? DEFAULT_TITLE_META_FILTER;

  /// 设置标题元数据过滤开关。
  ///
  /// 必须先同步 [TitleMetaFilter.enabled] 再落盘：标题过滤发生在 API
  /// 响应解析时（domain 层的解析工厂），那里读不到 Riverpod /
  /// SettingsManager，只能读纯 Dart 的静态标志。
  Future<void> setTitleMetaFilterEnabled(bool value) async {
    TitleMetaFilter.enabled = value;
    await _saveSetting(KEY_TITLE_META_FILTER, value);
  }

  /// 获取外观的文本描述
  String getAppearanceText(String mode) {
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

  // ============ 音频输出相关设置 ============
  //
  // 这四项的**唯一写入口是 PlayerCoordinator**（落盘之后还要推 A/B 两路
  // 播放器，见 `player_coordinator.dart` 的 setAudio* 系列）。这里的
  // setter 只给「读不到引擎也要能写」的场景兜底——目前没有调用方。

  /// 是否已同意音频输出页的免责说明（一次性闸门，同意后不再弹）。
  bool get audioOutputDisclaimerAccepted =>
      _cache[KEY_AUDIO_OUTPUT_DISCLAIMER] ?? DEFAULT_AUDIO_OUTPUT_DISCLAIMER;

  /// 同意免责说明。只有这一个键由 UI 直接写，它不进引擎。
  Future<void> setAudioOutputDisclaimerAccepted(bool value) async {
    await _saveSetting(KEY_AUDIO_OUTPUT_DISCLAIMER, value);
  }

  /// 音频延迟（毫秒，正数＝声音延后）。
  int get audioDelayMs => _cache[KEY_AUDIO_DELAY_MS] ?? DEFAULT_AUDIO_DELAY_MS;

  Future<void> setAudioDelayMs(int value) async {
    await _saveSetting(KEY_AUDIO_DELAY_MS, clampAudioDelay(value));
  }

  /// 硬件直通 / 独占模式（WASAPI · ALSA · CoreAudio）。
  bool get audioExclusive =>
      _cache[KEY_AUDIO_EXCLUSIVE] ?? DEFAULT_AUDIO_EXCLUSIVE;

  Future<void> setAudioExclusive(bool value) async {
    await _saveSetting(KEY_AUDIO_EXCLUSIVE, value);
  }

  /// 强制 DAC 采样率，`0` 表示跟随音源。
  int get audioSampleRate =>
      _cache[KEY_AUDIO_SAMPLERATE] ?? DEFAULT_AUDIO_SAMPLERATE;

  Future<void> setAudioSampleRate(int value) async {
    await _saveSetting(KEY_AUDIO_SAMPLERATE, value);
  }

  /// 输出设备的 mpv `Device.name`，空串表示跟随系统。
  String get audioDeviceName =>
      _cache[KEY_AUDIO_DEVICE] ?? DEFAULT_AUDIO_DEVICE;

  Future<void> setAudioDeviceName(String value) async {
    await _saveSetting(KEY_AUDIO_DEVICE, value);
  }

  /// 获取播放音质的文本描述
  String getAudioQualityText(String qualityId) {
    switch (qualityId) {
      case '30251':
        return 'Hi-Res 无损';
      case '30250':
        return '杜比全景声';
      case '30280':
        return '192K HQ';
      case '30232':
        return '132K SQ';
      case '30216':
        return '64K AAC-HE';
      default:
        return '192K HQ';
    }
  }
}
