/// 播放器高层状态（sealed class）
///
/// 把原本散落在 DualAudioService 的 5 个独立状态字段（AudioState /
/// CrossfadeState / _isPreloading / _isCrossfading / crossfadeCountdown）
/// 折叠成单字段 `ValueNotifier<PlayerState>`，消除 "先 set 再 check" 的
/// mutable 状态机反模式。
///
/// 转换关系（典型场景）：
///   PlayerIdle → PlayerBuffering → PlayerPlaying → PlayerPaused → PlayerPlaying
///   PlayerPlaying → PlayerCompleted → PlayerIdle
///   PlayerPlaying(fadeCountdown: N) 是 PlayerPlaying 的淡入淡出子态，
///   N=null 表示稳定播放，N=0..N 表示淡入淡出剩余秒。
sealed class PlayerState {
  const PlayerState();
}

final class PlayerIdle extends PlayerState {
  const PlayerIdle();
}

final class PlayerBuffering extends PlayerState {
  const PlayerBuffering();
}

/// 正在播放。`fadeCountdown` 为 null 时表示稳定播放；非 null 时为
/// crossfade 倒计时剩余秒（每秒刷新）。
final class PlayerPlaying extends PlayerState {
  final int? fadeCountdown;
  const PlayerPlaying({this.fadeCountdown});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayerPlaying && other.fadeCountdown == fadeCountdown);

  @override
  int get hashCode => Object.hash(runtimeType, fadeCountdown);
}

final class PlayerPaused extends PlayerState {
  const PlayerPaused();
}

/// 曲目自然结束（单曲循环 / 列表播完 等场景）。
final class PlayerCompleted extends PlayerState {
  const PlayerCompleted();
}
