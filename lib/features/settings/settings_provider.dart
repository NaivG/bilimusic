import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final String tabletMode;
  final bool fluidBackground;
  final bool blurEffect;
  final String audioQuality;
  final bool crossfadeEnabled;
  final int crossfadeDuration;
  final int preloadSeconds;
  final String lanSyncMode;
  final String lanSyncDeviceName;
  final String closeBehavior;

  // 音频输出四项 + 免责说明。
  //
  // 这里**只镜像、不提供 setter**：四项的唯一写入口是 PlayerCoordinator
  // （先落 SettingsManager 再推 A/B 两路播放器），UI 走
  // `audioOutputCommandsProvider`；manager `notifyListeners` 之后
  // [_onManagerChanged] 会把新值带回来。协议闸门是例外——它不进引擎，
  // 由 [SettingsNotifier.acceptAudioOutputDisclaimer] 直接委托 manager。
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
    this.tabletMode = 'auto',
    this.fluidBackground = true,
    this.blurEffect = true,
    this.audioQuality = '30280',
    this.crossfadeEnabled = false,
    this.crossfadeDuration = 3000,
    this.preloadSeconds = 10,
    this.lanSyncMode = 'off',
    this.lanSyncDeviceName = '',
    this.closeBehavior = 'prompt',
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
    String? tabletMode,
    bool? fluidBackground,
    bool? blurEffect,
    String? audioQuality,
    bool? crossfadeEnabled,
    int? crossfadeDuration,
    int? preloadSeconds,
    String? lanSyncMode,
    String? lanSyncDeviceName,
    String? closeBehavior,
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
      tabletMode: tabletMode ?? this.tabletMode,
      fluidBackground: fluidBackground ?? this.fluidBackground,
      blurEffect: blurEffect ?? this.blurEffect,
      audioQuality: audioQuality ?? this.audioQuality,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      preloadSeconds: preloadSeconds ?? this.preloadSeconds,
      lanSyncMode: lanSyncMode ?? this.lanSyncMode,
      lanSyncDeviceName: lanSyncDeviceName ?? this.lanSyncDeviceName,
      closeBehavior: closeBehavior ?? this.closeBehavior,
      audioOutputDisclaimerAccepted:
          audioOutputDisclaimerAccepted ?? this.audioOutputDisclaimerAccepted,
      audioDelayMs: audioDelayMs ?? this.audioDelayMs,
      audioExclusive: audioExclusive ?? this.audioExclusive,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioDeviceName: audioDeviceName ?? this.audioDeviceName,
    );
  }

  /// 从 manager 拉一份完整快照。[build] 与 [_onManagerChanged] 共用，
  /// 否则加字段时两处必然漏一边（历史上漏过）。
  factory SettingsState.fromManager(SettingsManager s) {
    return SettingsState(
      notificationsEnabled: s.notificationsEnabled,
      appearance: s.appearance,
      theme: s.theme,
      autoPlayNext: s.autoPlayNext,
      showLyrics: s.showLyrics,
      tabletMode: s.tabletMode,
      fluidBackground: s.fluidBackground,
      blurEffect: s.blurEffect,
      audioQuality: s.audioQuality,
      crossfadeEnabled: s.crossfadeEnabled,
      crossfadeDuration: s.crossfadeDuration,
      preloadSeconds: s.preloadSeconds,
      lanSyncMode: s.lanSyncMode,
      lanSyncDeviceName: s.lanSyncDeviceName,
      closeBehavior: s.closeBehavior,
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

  Future<void> setNotificationsEnabled(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await _save('notifications_enabled', value);
  }

  /// 委托给 SettingsManager 落盘并刷新其内存缓存：
  /// PlayerCoordinator 每次播放都读 manager.audioQuality，必须保证最新。
  Future<void> setAudioQuality(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setAudioQuality(value);
  }

  Future<void> setAppearance(String? value) async {
    if (value == null) return;
    state = state.copyWith(appearance: value);
    await _save('appearance', value);
  }

  Future<void> setTheme(String? value) async {
    if (value == null) return;
    state = state.copyWith(theme: value);
    await _save('theme', value);
  }

  Future<void> setAutoPlayNext(bool value) async {
    state = state.copyWith(autoPlayNext: value);
    await _save('auto_play_next', value);
  }

  Future<void> setShowLyrics(bool value) async {
    state = state.copyWith(showLyrics: value);
    await _save('show_lyrics', value);
  }

  Future<void> setTabletMode(String? value) async {
    if (value == null) return;
    state = state.copyWith(tabletMode: value);
    await _save('tablet_mode', value);
  }

  Future<void> setFluidBackground(bool value) async {
    state = state.copyWith(fluidBackground: value);
    await _save('fluid_background', value);
  }

  Future<void> setBlurEffect(bool value) async {
    state = state.copyWith(blurEffect: value);
    await _save('blur_effect', value);
  }

  /// 同意音频输出页的免责说明。不进引擎，直接委托 manager 落盘
  /// （同 [setCloseBehavior] 的「委托 + 刷新其内存缓存」写法），
  /// manager notify 之后 [_onManagerChanged] 会把新状态带回来。
  Future<void> acceptAudioOutputDisclaimer() async {
    await ref
        .read(_settingsManagerProvider)
        .setAudioOutputDisclaimerAccepted(true);
  }

  Future<void> setCrossfadeEnabled(bool value) async {
    state = state.copyWith(crossfadeEnabled: value);
    await _save('crossfade_enabled', value);
  }

  Future<void> setCrossfadeDuration(int value) async {
    final clamped = value.clamp(1000, 10000);
    final crossfadeSec = (clamped / 1000).ceil();
    if (crossfadeSec > state.preloadSeconds) {
      state = state.copyWith(preloadSeconds: crossfadeSec);
      await _save('preload_seconds', crossfadeSec);
    }
    state = state.copyWith(crossfadeDuration: clamped);
    await _save('crossfade_duration', clamped);
  }

  Future<void> setPreloadSeconds(int value) async {
    final clamped = value.clamp(5, 30);
    final crossfadeSec = (state.crossfadeDuration / 1000).ceil();
    final finalValue = clamped < crossfadeSec ? crossfadeSec : clamped;
    state = state.copyWith(preloadSeconds: finalValue);
    await _save('preload_seconds', finalValue);
  }

  Future<void> setLanSyncMode(String? value) async {
    if (value == null) return;
    state = state.copyWith(lanSyncMode: value);
    await _save('lan_sync_mode', value);
  }

  Future<void> setLanSyncDeviceName(String value) async {
    state = state.copyWith(lanSyncDeviceName: value);
    await _save('lan_sync_device_name', value);
  }

  /// 委托给 SettingsManager 落盘并刷新其内存缓存：
  /// 窗口监听器在关闭时同步读 manager.closeBehavior，必须保证最新。
  Future<void> setCloseBehavior(String? value) async {
    if (value == null) return;
    await ref.read(_settingsManagerProvider).setCloseBehavior(value);
  }

  Future<void> _save(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      }
    } catch (e) {
      debugPrint('Error saving setting $key: $e');
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
