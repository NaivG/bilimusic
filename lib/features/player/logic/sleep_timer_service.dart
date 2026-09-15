import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 定时关闭所处阶段。
enum SleepTimerPhase {
  /// 未启用。
  idle,

  /// 倒计时进行中。
  counting,

  /// 倒计时已结束，等待当前歌曲播放完毕再暂停（仅「播完整首」模式）。
  waitingTrackEnd,
}

/// 定时关闭的对外只读状态（供 UI 订阅渲染）。
class SleepTimerUiState {
  final SleepTimerPhase phase;

  /// 倒计时剩余毫秒（counting 阶段有效）。
  final int remainingMs;

  /// 本次设定的总时长毫秒。
  final int totalMs;

  /// 是否「播完整首再停止」。
  final bool finishCurrentTrack;

  const SleepTimerUiState({
    required this.phase,
    this.remainingMs = 0,
    this.totalMs = 0,
    this.finishCurrentTrack = false,
  });

  bool get isActive => phase != SleepTimerPhase.idle;

  SleepTimerUiState copyWith({
    SleepTimerPhase? phase,
    int? remainingMs,
    int? totalMs,
    bool? finishCurrentTrack,
  }) {
    return SleepTimerUiState(
      phase: phase ?? this.phase,
      remainingMs: remainingMs ?? this.remainingMs,
      totalMs: totalMs ?? this.totalMs,
      finishCurrentTrack: finishCurrentTrack ?? this.finishCurrentTrack,
    );
  }
}

/// 定时关闭服务。
///
/// 基于 [StopWatchTimer] 的 countDown 模式实现：
/// - 默认到点暂停播放（[PlayerCoordinator.pause]）；
/// - 可选「播完整首再停止」：到点不立即暂停，而是给协调器挂上
///   「当前歌曲播完后暂停」标记，由曲目完成事件触发暂停，
///   期间抑制 crossfade / 自动切歌。
class SleepTimerService {
  SleepTimerService({required PlayerCoordinator coordinator})
    : _coordinator = coordinator {
    _coordinator.pauseAfterCurrentTrack.addListener(_onArmedFlagChanged);
    // 「更多」菜单实时文案与状态保持同步。
    state.addListener(_syncMenuLabel);
    _syncMenuLabel();
  }

  final PlayerCoordinator _coordinator;

  StopWatchTimer? _watch;
  bool _finishCurrentTrack = false;
  bool _disposed = false;

  /// UI 订阅入口。
  final ValueNotifier<SleepTimerUiState> state = ValueNotifier(
    const SleepTimerUiState(phase: SleepTimerPhase.idle),
  );

  /// 「更多」菜单入口文案 listenable —— 底部操作单传给
  /// `SheetAction.labelListenable` 即可随倒计时实时刷新。
  final ValueNotifier<String> menuLabel = ValueNotifier('定时关闭');

  /// 当前状态快照（非订阅读取）。
  SleepTimerUiState get uiState => state.value;

  bool get isActive => state.value.isActive;

  /// 状态变化 → 同步「更多」菜单文案。
  void _syncMenuLabel() {
    menuLabel.value = sleepTimerMenuLabel(state.value);
  }

  /// 启动（或重启）定时。
  void start(Duration duration, {bool? finishCurrentTrack}) {
    if (_disposed || duration <= Duration.zero) return;
    if (finishCurrentTrack != null) _finishCurrentTrack = finishCurrentTrack;

    // 重启时清掉上一轮遗留的「播完暂停」标记，语义以最新一次设定为准。
    _coordinator.cancelPauseAfterCurrentTrack();

    _teardownWatch();
    final watch = StopWatchTimer(
      mode: StopWatchMode.countDown,
      presetMillisecond: duration.inMilliseconds,
      refreshTime: 250,
      onChange: _onTick,
      onEnded: _onCountdownEnded,
    );
    _watch = watch;
    watch.onStartTimer();

    state.value = SleepTimerUiState(
      phase: SleepTimerPhase.counting,
      remainingMs: duration.inMilliseconds,
      totalMs: duration.inMilliseconds,
      finishCurrentTrack: _finishCurrentTrack,
    );
  }

  /// 取消定时。
  void cancel() {
    if (_disposed) return;
    if (state.value.phase == SleepTimerPhase.waitingTrackEnd) {
      _coordinator.cancelPauseAfterCurrentTrack();
    }
    _teardownWatch();
    _finishCurrentTrack = false;
    state.value = const SleepTimerUiState(phase: SleepTimerPhase.idle);
  }

  /// 延长时长（仅倒计时阶段有效）。
  void extend(Duration extra) {
    if (_disposed || extra <= Duration.zero) return;
    if (state.value.phase != SleepTimerPhase.counting) return;

    // setPresetTime(add: true) 会同步触发 onChange 刷新 remainingMs。
    _watch?.setPresetTime(mSec: extra.inMilliseconds, add: true);
    final after = state.value;
    state.value = after.copyWith(totalMs: after.totalMs + extra.inMilliseconds);
  }

  /// 运行中切换「播完整首再停止」。
  ///
  /// 已进入等待阶段时从开切到关：语义变为「立即暂停」并结束定时。
  void setFinishCurrentTrack(bool value) {
    if (_disposed) return;
    _finishCurrentTrack = value;
    final s = state.value;
    state.value = s.copyWith(finishCurrentTrack: value);

    if (!value && s.phase == SleepTimerPhase.waitingTrackEnd) {
      _coordinator.cancelPauseAfterCurrentTrack();
      _coordinator.pause();
      _teardownWatch();
      state.value = const SleepTimerUiState(phase: SleepTimerPhase.idle);
    }
  }

  void _onTick(int remainingMs) {
    if (_disposed) return;
    final s = state.value;
    if (s.phase != SleepTimerPhase.counting) return;
    state.value = s.copyWith(remainingMs: remainingMs);
  }

  void _onCountdownEnded() {
    if (_disposed) return;
    final s = state.value;
    if (s.phase != SleepTimerPhase.counting) return;

    if (_finishCurrentTrack && _coordinator.isPlaying) {
      // 不立即暂停：等当前歌曲播完，由完成事件触发暂停。
      _coordinator.armPauseAfterCurrentTrack();
      state.value = s.copyWith(phase: SleepTimerPhase.waitingTrackEnd);
      return;
    }

    _teardownWatch();
    _finishCurrentTrack = false;
    state.value = const SleepTimerUiState(phase: SleepTimerPhase.idle);
    // 默认行为：到点暂停播放。
    _coordinator.pause();
  }

  /// 协调器「播完暂停」标记变化 → 同步等待阶段状态。
  void _onArmedFlagChanged() {
    if (_disposed) return;
    final armed = _coordinator.pauseAfterCurrentTrack.value;
    if (!armed && state.value.phase == SleepTimerPhase.waitingTrackEnd) {
      // 已暂停 / 被手动切歌等操作清除 → 定时流程结束。
      _finishCurrentTrack = false;
      state.value = const SleepTimerUiState(phase: SleepTimerPhase.idle);
    }
  }

  void _teardownWatch() {
    final watch = _watch;
    _watch = null;
    if (watch == null) return;
    watch.onStopTimer();
    unawaited(watch.dispose().catchError((_) {}));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    state.removeListener(_syncMenuLabel);
    _coordinator.pauseAfterCurrentTrack.removeListener(_onArmedFlagChanged);
    final watch = _watch;
    _watch = null;
    await watch?.dispose().catchError((_) {});
    state.dispose();
    menuLabel.dispose();
  }
}

/// 「更多」菜单入口文案：启用时附带剩余时间 / 等待状态。
String sleepTimerMenuLabel(SleepTimerUiState s) {
  switch (s.phase) {
    case SleepTimerPhase.idle:
      return '定时关闭';
    case SleepTimerPhase.counting:
      return '定时关闭 · ${formatSleepRemaining(s.remainingMs)}';
    case SleepTimerPhase.waitingTrackEnd:
      return '定时关闭 · 播完本曲后停止';
  }
}

/// 剩余时间展示，复用全库唯一的 [formatDuration]（MM:SS / H:MM:SS）。
String formatSleepRemaining(int remainingMs) {
  // 向上取整到秒：避免剩余不足 1 秒时显示成 "0:00" 的假象。
  final remainder = remainingMs % 1000;
  final seconds = remainingMs ~/ 1000 + (remainder == 0 ? 0 : 1);
  return formatDuration(Duration(seconds: seconds));
}
