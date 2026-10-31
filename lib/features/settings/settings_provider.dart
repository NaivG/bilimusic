import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';

final _settingsManagerProvider = settingsManagerProvider;

@immutable
class SettingsState {
  final bool notificationsEnabled;
  final String appearance;
  final String theme;
  final bool autoPlayNext;
  final bool showLyrics;
  final bool fluidBackground;
  final bool blurEffect;
  final String audioQuality;
  final bool crossfadeEnabled;
  final int crossfadeDuration;

  /// 自动过渡：过渡位置与时长按曲目时长推导，忽略 [crossfadeDuration]。
  final bool crossfadeAuto;
  final int preloadSeconds;
  final String lanSyncMode;
  final String lanSyncDeviceName;
  final String closeBehavior;

  /// 标题元数据过滤（实验性）。
  final bool titleMetaFilterEnabled;

  // 音频输出四项 + 免责说明。
  //
  // 四项的唯一写入口是 PlayerCoordinator（先落 SettingsManager 再推
  // A/B 两路播放器），UI 走`audioOutputCommandsProvider`；manager
  //`notifyListeners` 之后[_onManagerChanged] 会把新值带回来。
  // 协议闸门例外——它不进引擎，由 [SettingsNotifier.acceptAudioOutputDisclaimer] 直接委托 manager。
  final bool audioOutputDisclaimerAccepted;
  final int audioDelayMs;
  final bool audioExclusive;
  final int audioSampleRate;
  final String audioDeviceName;

  const SettingsState({
    this.notificationsEnabled = true,
    this.appearance = 'system',
    this.theme = 'lucent',
    this.autoPlayNext = true,
    this.showLyrics = true,
    this.fluidBackground = true,
    this.blurEffect = true,
    this.audioQuality = '30280',
    this.crossfadeEnabled = false,
    this.crossfadeDuration = 3000,
    this.crossfadeAuto = false,
    this.preloadSeconds = 10,
    this.lanSyncMode = 'off',
    this.lanSyncDeviceName = '',
    this.closeBehavior = 'prompt',
    this.titleMetaFilterEnabled = false,
    this.audioOutputDisclaimerAccepted = false,
    this.audioDelayMs = 0,
    this.audioExclusive = false,
    this.audioSampleRate = 0,
    this.audioDeviceName = '',
  });

  SettingsState copyWith({
    bool? notificationsEnabled,
    String? appearance,
    String? theme,
    bool? autoPlayNext,
    bool? showLyrics,
    bool? fluidBackground,
    bool? blurEffect,
    String? audioQuality,
    bool? crossfadeEnabled,
    int? crossfadeDuration,
    bool? crossfadeAuto,
    int? preloadSeconds,
    String? lanSyncMode,
    String? lanSyncDeviceName,
    String? closeBehavior,
    bool? titleMetaFilterEnabled,
    bool? audioOutputDisclaimerAccepted,
    int? audioDelayMs,
    bool? audioExclusive,
    int? audioSampleRate,
    String? audioDeviceName,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      appearance: appearance ?? this.appearance,
      theme: theme ?? this.theme,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      showLyrics: showLyrics ?? this.showLyrics,
      fluidBackground: fluidBackground ?? this.fluidBackground,
      blurEffect: blurEffect ?? this.blurEffect,
      audioQuality: audioQuality ?? this.audioQuality,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      crossfadeAuto: crossfadeAuto ?? this.crossfadeAuto,
      preloadSeconds: preloadSeconds ?? this.preloadSeconds,
      lanSyncMode: lanSyncMode ?? this.lanSyncMode,
      lanSyncDeviceName: lanSyncDeviceName ?? this.lanSyncDeviceName,
      closeBehavior: closeBehavior ?? this.closeBehavior,
      titleMetaFilterEnabled:
          titleMetaFilterEnabled ?? this.titleMetaFilterEnabled,
      audioOutputDisclaimerAccepted:
          audioOutputDisclaimerAccepted ?? this.audioOutputDisclaimerAccepted,
      audioDelayMs: audioDelayMs ?? this.audioDelayMs,
      audioExclusive: audioExclusive ?? this.audioExclusive,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioDeviceName: audioDeviceName ?? this.audioDeviceName,
    );
  }

  /// 从 manager 拉一份完整快照。[build] 与 [_onManagerChanged] 共用，
  /// 否则加字段时两处必然漏一边。
  factory SettingsState.fromManager(SettingsManager s) {
    return SettingsState(
      notificationsEnabled: s.notificationsEnabled,
      appearance: s.appearance,
      theme: s.theme,
      autoPlayNext: s.autoPlayNext,
      showLyrics: s.showLyrics,
      fluidBackground: s.fluidBackground,
      blurEffect: s.blurEffect,
      audioQuality: s.audioQuality,
      crossfadeEnabled: s.crossfadeEnabled,
      crossfadeDuration: s.crossfadeDuration,
      crossfadeAuto: s.crossfadeAuto,
      preloadSeconds: s.preloadSeconds,
      lanSyncMode: s.lanSyncMode,
      lanSyncDeviceName: s.lanSyncDeviceName,
      closeBehavior: s.closeBehavior,
      titleMetaFilterEnabled: s.titleMetaFilterEnabled,
      audioOutputDisclaimerAccepted: s.audioOutputDisclaimerAccepted,
      audioDelayMs: s.audioDelayMs,
      audioExclusive: s.audioExclusive,
      audioSampleRate: s.audioSampleRate,
      audioDeviceName: s.audioDeviceName,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final s = ref.read(_settingsManagerProvider);
    s.addListener(_onManagerChanged);
    ref.onDispose(() => s.removeListener(_onManagerChanged));
    return SettingsState.fromManager(s);
  }

  void _onManagerChanged() {
    state = SettingsState.fromManager(ref.read(_settingsManagerProvider));
  }

  /// 委托给 SettingsManager：开关的内存缓存由 manager 持有，
  /// manager notify 之后由 [_onManagerChanged] 把新状态带回来。
  Future<void> setNotificationsEnabled(bool value) async {
    await ref.read(_settingsManagerProvider).setNotificationsEnabled(value);
  }

  /// 委托给 SettingsManager 落盘并刷新其内存缓存：
  /// PlayerCoordinator 每次播放都读 manager.audioQuality，必须保证最新。
  Future<void> setAudioQuality(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setAudioQuality(value);
  }

  Future<void> setAppearance(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setAppearance(value);
  }

  Future<void> setTheme(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setTheme(value);
  }

  /// 委托给 SettingsManager：manager notify 之后
  /// [_onManagerChanged] 会把新状态带回来。
  Future<void> setAutoPlayNext(bool value) async {
    await ref.read(_settingsManagerProvider).setAutoPlayNext(value);
  }

  Future<void> setShowLyrics(bool value) async {
    await ref.read(_settingsManagerProvider).setShowLyrics(value);
  }

  Future<void> setFluidBackground(bool value) async {
    await ref.read(_settingsManagerProvider).setFluidBackground(value);
  }

  Future<void> setBlurEffect(bool value) async {
    await ref.read(_settingsManagerProvider).setBlurEffect(value);
  }

  /// 同意音频输出页的免责说明。不进引擎，直接委托 manager 落盘
  /// （同 [setCloseBehavior] 的「委托 + 刷新其内存缓存」写法），
  /// manager notify 之后 [_onManagerChanged] 会把新状态带回来。
  Future<void> acceptAudioOutputDisclaimer() async {
    await ref
        .read(_settingsManagerProvider)
        .setAudioOutputDisclaimerAccepted(true);
  }

  /// 委托给 SettingsManager：
  /// PlayerCoordinator 每次触发过渡都读 manager.crossfadeEnabled /
  /// crossfadeDuration / preloadSeconds 的内存缓存。
  Future<void> setCrossfadeEnabled(bool value) async {
    await ref.read(_settingsManagerProvider).setCrossfadeEnabled(value);
  }

  /// 委托给 SettingsManager：夹取范围（1–10 秒）与「时长不得超过预加载
  /// 时间」的不变量由 manager 统一维护。
  Future<void> setCrossfadeDuration(int value) async {
    await ref.read(_settingsManagerProvider).setCrossfadeDuration(value);
  }

  /// 委托给 SettingsManager。
  Future<void> setCrossfadeAuto(bool value) async {
    await ref.read(_settingsManagerProvider).setCrossfadeAuto(value);
  }

  /// 委托给 SettingsManager：夹取范围（5–30 秒）与「不得小于淡入淡出
  /// 时长」的不变量由 manager 统一维护。
  Future<void> setPreloadSeconds(int value) async {
    await ref.read(_settingsManagerProvider).setPreloadSeconds(value);
  }

  /// 委托给 SettingsManager（理由见 [setAutoPlayNext]）：
  /// LanSyncService 监听 manager 的 notifyListeners 在运行时切换模式。
  Future<void> setLanSyncMode(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setLanSyncMode(value);
  }

  Future<void> setLanSyncDeviceName(String value) async {
    await ref.read(_settingsManagerProvider).setLanSyncDeviceName(value);
  }

  /// 委托给 SettingsManager 落盘并刷新其内存缓存：
  /// 窗口监听器在关闭时同步读 manager.closeBehavior，必须保证最新。
  Future<void> setCloseBehavior(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setCloseBehavior(value);
  }

  /// 委托给 SettingsManager：除了落盘还要同步 TitleMetaFilter 静态开关
  /// （API 解析入口读的是它），manager notify 之后 [_onManagerChanged]
  /// 会把新状态带回来。
  Future<void> setTitleMetaFilterEnabled(bool value) async {
    await ref.read(_settingsManagerProvider).setTitleMetaFilterEnabled(value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
