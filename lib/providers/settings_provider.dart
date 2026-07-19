import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/core/app_providers.dart';

final _settingsManagerProvider = settingsManagerProvider;

@immutable
class SettingsState {
  final bool notificationsEnabled;
  final bool downloadQualityHigh;
  final String appearance;
  final String theme;
  final bool autoPlayNext;
  final bool showLyrics;
  final String tabletMode;
  final bool fluidBackground;
  final bool blurEffect;
  final String audioOutputMode;
  final bool crossfadeEnabled;
  final int crossfadeDuration;
  final int preloadSeconds;

  const SettingsState({
    this.notificationsEnabled = true,
    this.downloadQualityHigh = true,
    this.appearance = 'system',
    this.theme = 'lucent',
    this.autoPlayNext = true,
    this.showLyrics = true,
    this.tabletMode = 'auto',
    this.fluidBackground = true,
    this.blurEffect = true,
    this.audioOutputMode = 'audiotrack',
    this.crossfadeEnabled = false,
    this.crossfadeDuration = 3000,
    this.preloadSeconds = 10,
  });

  SettingsState copyWith({
    bool? notificationsEnabled,
    bool? downloadQualityHigh,
    String? appearance,
    String? theme,
    bool? autoPlayNext,
    bool? showLyrics,
    String? tabletMode,
    bool? fluidBackground,
    bool? blurEffect,
    String? audioOutputMode,
    bool? crossfadeEnabled,
    int? crossfadeDuration,
    int? preloadSeconds,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      downloadQualityHigh: downloadQualityHigh ?? this.downloadQualityHigh,
      appearance: appearance ?? this.appearance,
      theme: theme ?? this.theme,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      showLyrics: showLyrics ?? this.showLyrics,
      tabletMode: tabletMode ?? this.tabletMode,
      fluidBackground: fluidBackground ?? this.fluidBackground,
      blurEffect: blurEffect ?? this.blurEffect,
      audioOutputMode: audioOutputMode ?? this.audioOutputMode,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      preloadSeconds: preloadSeconds ?? this.preloadSeconds,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final s = ref.read(_settingsManagerProvider);
    s.addListener(_onManagerChanged);
    ref.onDispose(() => s.removeListener(_onManagerChanged));
    return SettingsState(
      notificationsEnabled: s.notificationsEnabled,
      downloadQualityHigh: s.downloadQualityHigh,
      appearance: s.appearance,
      theme: s.theme,
      autoPlayNext: s.autoPlayNext,
      showLyrics: s.showLyrics,
      tabletMode: s.tabletMode,
      fluidBackground: s.fluidBackground,
      blurEffect: s.blurEffect,
      audioOutputMode: s.audioOutputMode,
      crossfadeEnabled: s.crossfadeEnabled,
      crossfadeDuration: s.crossfadeDuration,
      preloadSeconds: s.preloadSeconds,
    );
  }

  void _onManagerChanged() {
    final s = ref.read(_settingsManagerProvider);
    state = SettingsState(
      notificationsEnabled: s.notificationsEnabled,
      downloadQualityHigh: s.downloadQualityHigh,
      appearance: s.appearance,
      theme: s.theme,
      autoPlayNext: s.autoPlayNext,
      showLyrics: s.showLyrics,
      tabletMode: s.tabletMode,
      fluidBackground: s.fluidBackground,
      blurEffect: s.blurEffect,
      audioOutputMode: s.audioOutputMode,
      crossfadeEnabled: s.crossfadeEnabled,
      crossfadeDuration: s.crossfadeDuration,
      preloadSeconds: s.preloadSeconds,
    );
  }

  Future<void> setNotificationsEnabled(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await _save('notifications_enabled', value);
  }

  Future<void> setDownloadQualityHigh(bool value) async {
    state = state.copyWith(downloadQualityHigh: value);
    await _save('download_quality_high', value);
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

  Future<void> setAudioOutputMode(String? value) async {
    if (value == null) return;
    state = state.copyWith(audioOutputMode: value);
    await _save('audio_output_mode', value);
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
