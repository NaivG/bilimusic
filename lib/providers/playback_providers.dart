import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/services/player_coordinator.dart';

// 引入 playlist providers 的 currentPlaylistProvider / currentIndexProvider，
// 供本文件的派生 provider 监听 playlist 变化。
import 'package:bilimusic/providers/playlist_providers.dart'
    show currentPlaylistProvider, currentIndexProvider;

final _dualAudioServiceProvider = dualAudioServiceProvider;
final _playerCoordinatorProvider = playerCoordinatorProvider;

class _PlayerStateWatcher extends Notifier<PlayerState> {
  @override
  PlayerState build() {
    final vn =
        ref.read(_dualAudioServiceProvider).playerState
            as ValueNotifier<PlayerState>;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() => state =
      (ref.read(_dualAudioServiceProvider).playerState
              as ValueNotifier<PlayerState>)
          .value;
}

final playerStateProvider = NotifierProvider<_PlayerStateWatcher, PlayerState>(
  _PlayerStateWatcher.new,
);

class _PositionWatcher extends Notifier<Duration> {
  @override
  Duration build() {
    final vn = ref.read(_dualAudioServiceProvider).position;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_dualAudioServiceProvider).position.value;
}

final positionProvider = NotifierProvider<_PositionWatcher, Duration>(
  _PositionWatcher.new,
);

class _DurationWatcher extends Notifier<Duration> {
  @override
  Duration build() {
    final vn = ref.read(_dualAudioServiceProvider).duration;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_dualAudioServiceProvider).duration.value;
}

final durationProvider = NotifierProvider<_DurationWatcher, Duration>(
  _DurationWatcher.new,
);

class _PlayModeWatcher extends Notifier<PlayMode> {
  @override
  PlayMode build() {
    final vn = ref.read(_dualAudioServiceProvider).playMode;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_dualAudioServiceProvider).playMode.value;
}

final playModeProvider = NotifierProvider<_PlayModeWatcher, PlayMode>(
  _PlayModeWatcher.new,
);

class _VolumeWatcher extends Notifier<double> {
  @override
  double build() {
    final vn = ref.read(_dualAudioServiceProvider).volume;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_dualAudioServiceProvider).volume.value;
}

final volumeProvider = NotifierProvider<_VolumeWatcher, double>(
  _VolumeWatcher.new,
);

/// 派生：当前正在播放的音乐（来自 PlayerCoordinator 内部的 playlist+index 组合）
final currentMusicFromCoordinatorProvider = Provider<Music?>((ref) {
  final pc = ref.read(_playerCoordinatorProvider);
  ref.watch(currentPlaylistProvider);
  ref.watch(currentIndexProvider);
  return pc.currentMusic;
});

/// 派生：当前播放列表 + index 的同步快照（用于 UI 非监听场景）
final coordinatorPlaylistProvider = Provider<List<Music>>((ref) {
  final pc = ref.read(_playerCoordinatorProvider);
  ref.watch(currentPlaylistProvider);
  return pc.playlist.value;
});

/// 播放器命令 - UI 操作 PlayerCoordinator 的统一入口。
class PlaybackCommands extends Notifier<void> {
  PlayerCoordinator get _pc => ref.read(_playerCoordinatorProvider);
  DualAudioService get _dual => ref.read(_dualAudioServiceProvider);

  @override
  void build() {}

  Future<void> playMusic(Music music) => _pc.playMusic(music);
  Future<void> pause() => _pc.pause();
  Future<void> resume() => _pc.resume();
  Future<void> stop() => _pc.stop();
  Future<void> seek(Duration position) => _pc.seek(position);
  void togglePlayMode() => _pc.togglePlayMode();
  Future<void> playNext() => _pc.playNext();
  Future<void> playPrevious() => _pc.playPrevious();
  Future<void> playAtIndex(int index) => _pc.playAtIndex(index);

  Future<void> addToPlaylist(Music music) => _pc.addToPlaylist(music);
  Future<void> addAllToPlaylist(List<Music> musics) =>
      _pc.addAllToPlaylist(musics);
  Future<void> removeFromPlaylist(Music music) => _pc.removeFromPlaylist(music);
  Future<void> clearPlaylist() => _pc.clearPlaylist();
  Future<void> moveInPlaylist(int from, int to) => _pc.moveInPlaylist(from, to);
  Future<void> playNextFromIndex(Music music) => _pc.playNextFromIndex(music);

  Future<void> addToFavorites(Music music) => _pc.addToFavorites(music);
  Future<void> removeFromFavorites(Music music) =>
      _pc.removeFromFavorites(music);
  bool isFavorite(Music music) => _pc.isFavorite(music);

  Future<void> setVolume(double value) => _dual.setVolume(value);
  Future<void> toggleMute() => _dual.toggleMute();

  Duration get currentPosition => _dual.currentPosition;
  Duration get currentDuration => _dual.currentDuration;
  bool get isPlaying => _dual.isPlaying;
  bool get isFading => _dual.isFading;
  double get progressPercentage => _dual.progressPercentage;
}

final playbackCommandsProvider = NotifierProvider<PlaybackCommands, void>(
  PlaybackCommands.new,
);
