import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_lyric/flutter_lyric.dart';

import 'package:bilimusic/features/player/models/player_state.dart';

/// 把播放器的位置接到 `flutter_lyric` 4.x 的 [LyricProgressSource]，
/// 由 Controller 在可见、启用且播放中时按帧采样。
class PlayerLyricProgressSource implements LyricProgressSource {
  PlayerLyricProgressSource({
    required this.positionTicks,
    required this.playerState,
    required this.readPosition,
  }) {
    positionTicks.addListener(_emit);
    playerState.addListener(_emit);
  }

  final ValueListenable<Duration> positionTicks;
  final ValueListenable<PlayerState> playerState;
  final Duration Function() readPosition;

  /// 非同步广播：控制器在回调里采样并发布状态，同步派发容易在
  /// ValueNotifier 的通知链里重入。
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// 已经对外发布过的位置。
  ///
  /// (只针对) libmpv 的时钟在起播/换轨瞬间会短暂回吐一个更旧的值（含 0），
  /// 直接透传会让歌词整体倒退。这里只允许位置前进，真实的向后 seek
  /// （跨度明显大于抖动）则接受。
  Duration? _last;

  /// 判定「向后 seek」而不是时钟抖动的阈值。
  static const Duration rewindTolerance = Duration(milliseconds: 400);

  bool _disposed = false;

  @override
  Duration get position {
    if (_disposed) return _last ?? Duration.zero;
    final raw = readPosition();
    final last = _last;
    // 只有「播放中」的小幅后退才当作时钟抖动；暂停/缓冲时的后退是用户
    // 在 seek，必须原样接受，否则歌词会停在原地不动。
    final holdBack =
        last != null &&
        raw < last &&
        isAdvancing &&
        last - raw <= rewindTolerance;
    if (holdBack) return last;
    _last = raw;
    return raw;
  }

  @override
  bool get isAdvancing => !_disposed && playerState.value is PlayerPlaying;

  @override
  Stream<void> get changes => _changes.stream;

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    positionTicks.removeListener(_emit);
    playerState.removeListener(_emit);
    _changes.close();
  }
}
