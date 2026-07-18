import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/models/play_mode.dart';

class _PlayerStateWatcher extends Notifier<PlayerState> {
  @override
  PlayerState build() {
    final vn = sl.dualAudioService.playerState as ValueNotifier<PlayerState>;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = (sl.dualAudioService.playerState as ValueNotifier<PlayerState>).value;
}

final playerStateProvider =
    NotifierProvider<_PlayerStateWatcher, PlayerState>(
  _PlayerStateWatcher.new,
);

class _PositionWatcher extends Notifier<Duration> {
  @override
  Duration build() {
    final vn = sl.dualAudioService.position;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() => state = sl.dualAudioService.position.value;
}

final positionProvider =
    NotifierProvider<_PositionWatcher, Duration>(
  _PositionWatcher.new,
);

class _DurationWatcher extends Notifier<Duration> {
  @override
  Duration build() {
    final vn = sl.dualAudioService.duration;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() => state = sl.dualAudioService.duration.value;
}

final durationProvider =
    NotifierProvider<_DurationWatcher, Duration>(
  _DurationWatcher.new,
);

class _PlayModeWatcher extends Notifier<PlayMode> {
  @override
  PlayMode build() {
    final vn = sl.dualAudioService.playMode;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() => state = sl.dualAudioService.playMode.value;
}

final playModeProvider =
    NotifierProvider<_PlayModeWatcher, PlayMode>(
  _PlayModeWatcher.new,
);
