import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lyrics/lyric_progress_source.dart';
import 'package:bilimusic/features/player/models/player_state.dart';

void main() {
  late ValueNotifier<Duration> ticks;
  late ValueNotifier<PlayerState> state;
  late Duration raw;
  late PlayerLyricProgressSource source;

  setUp(() {
    ticks = ValueNotifier(Duration.zero);
    state = ValueNotifier(const PlayerIdle());
    raw = Duration.zero;
    source = PlayerLyricProgressSource(
      positionTicks: ticks,
      playerState: state,
      readPosition: () => raw,
    );
  });

  tearDown(() {
    source.dispose();
    ticks.dispose();
    state.dispose();
  });

  test('播放中位置只前进：时钟轻微回吐时保持上一次的值', () {
    state.value = const PlayerPlaying();
    raw = const Duration(seconds: 10);
    expect(source.position, const Duration(seconds: 10));

    // libmpv 起播/换轨瞬间回吐一个更旧的值。
    raw = const Duration(seconds: 9, milliseconds: 900);
    expect(source.position, const Duration(seconds: 10));

    // 继续前进就正常发布。
    raw = const Duration(seconds: 10, milliseconds: 500);
    expect(source.position, const Duration(seconds: 10, milliseconds: 500));
  });

  test('真实的向后 seek 要接受，不能被单调保持吃掉', () {
    state.value = const PlayerPlaying();
    raw = const Duration(seconds: 30);
    expect(source.position, const Duration(seconds: 30));

    raw = const Duration(seconds: 5);
    expect(source.position, const Duration(seconds: 5));
  });

  test('暂停时的小幅回退是用户 seek，必须原样接受', () {
    state.value = const PlayerPlaying();
    raw = const Duration(seconds: 10);
    expect(source.position, const Duration(seconds: 10));

    state.value = const PlayerPaused();
    raw = const Duration(seconds: 9, milliseconds: 800);
    expect(source.position, const Duration(seconds: 9, milliseconds: 800));
  });

  test('播放中回退幅度在阈值边界上按抖动处理', () {
    state.value = const PlayerPlaying();
    raw = const Duration(seconds: 10);
    expect(source.position, const Duration(seconds: 10));

    raw =
        const Duration(seconds: 10) - PlayerLyricProgressSource.rewindTolerance;
    expect(source.position, const Duration(seconds: 10));

    raw =
        const Duration(seconds: 10) -
        PlayerLyricProgressSource.rewindTolerance -
        const Duration(milliseconds: 1);
    expect(source.position, raw);
  });

  test('isAdvancing 只认 PlayerPlaying', () {
    expect(source.isAdvancing, isFalse);
    state.value = const PlayerBuffering();
    expect(source.isAdvancing, isFalse);
    state.value = const PlayerPlaying();
    expect(source.isAdvancing, isTrue);
    state.value = const PlayerPaused();
    expect(source.isAdvancing, isFalse);
    state.value = const PlayerCompleted();
    expect(source.isAdvancing, isFalse);
  });

  test('播放位置 tick 与状态变化都会通知订阅者', () async {
    final events = <void>[];
    final sub = source.changes.listen(events.add);
    addTearDown(sub.cancel);

    ticks.value = const Duration(seconds: 1);
    state.value = const PlayerPlaying();
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 2);
  });

  test('dispose 之后不再读播放器，也不再派发事件', () async {
    raw = const Duration(seconds: 2);
    expect(source.position, const Duration(seconds: 2));

    final events = <void>[];
    final sub = source.changes.listen(events.add);
    addTearDown(sub.cancel);

    source.dispose();

    // 播放器此时可能已经释放在先：再读 raw 是不合法的，必须走已发布值。
    raw = const Duration(seconds: 9);
    expect(source.position, const Duration(seconds: 2));
    expect(source.isAdvancing, isFalse);

    ticks.value = const Duration(seconds: 3);
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
  });
}
