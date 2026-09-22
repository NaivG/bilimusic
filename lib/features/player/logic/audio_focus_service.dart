import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/player/models/player_state.dart';

/// 音频焦点补偿服务。
///
/// 系统媒体会话由 audio_service 独占（两个 Player 都不调 setMediaSession），
/// 引擎侧由本服务接管焦点。
///
/// 这里用 audio_session 实现音频焦点补偿，语义逐条
/// 对齐其 `handleInterruptions` 实现：
///
/// - `configure(music)`：usage=media / contentType=music 的标准音乐配方
///   （对应 just_audio 的 androidApplyAudioAttributes）；
/// - `interruptionEventStream`：
///   - begin(pause/unknown) 且正在播 → 暂停，并标记「因打断而暂停」；
///   - end(pause) → 只在「因打断而暂停」时自动恢复；永久失去焦点
///     （AUDIOFOCUS_LOSS）映射为 end(unknown)，绝不自动恢复；
///   - duck 不动作：media usage 语义（just_audio 仅对 game 减半音量）；
/// - `becomingNoisyEventStream`：拔耳机即暂停（不标记，不自动恢复）；
/// - 进入播放态时 `setActive(true)` 申请焦点（对应 just_audio 的
///   handleAudioSessionActivation）。**必须调**：Android 侧的打断事件
///   只从 requestAudioFocus 注册的监听里产生，不申请焦点就没有事件。
///
/// 桌面端（Windows / Linux）audio_session 是安全 no-op：configure 的
/// invokeMethod 异常被包内部吞掉，setActive 不落到任何平台分支直接返回
/// true；macOS / iOS / Android 上是真实调用。
class AudioFocusService {
  AudioFocusService({required PlayerCoordinator coordinator})
    : _coordinator = coordinator;

  final PlayerCoordinator _coordinator;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  bool _configured = false;

  /// 「因打断而暂停」标记。只由打断事件读写；进入播放态（用户主动恢复）
  /// 或 stop（Idle / Completed）时清除。与 just_audio 的 `_playInterrupted`
  /// 一致：它的 pause() 在 !playing 时早退、不清标记，所以
  /// PlayerPaused / PlayerBuffering 的状态变化在这里不碰它。
  bool _interruptedWhilePlaying = false;
  bool _wasPlaying = false;

  /// 最近一次 `setActive(true)` 的结果（null = 还没申请过）。
  bool? _lastActivateOk;

  /// 申请焦点的次数（正常播放里每次进入播放态都会 +1）。
  int _activateCount = 0;

  /// 诊断用：audio_session 是否已完成配置（false = 打断 / 拔耳机都不会暂停）。
  bool get isConfigured => _configured;

  /// 诊断用：最近一次申请音频焦点的结果。
  bool? get lastActivateOk => _lastActivateOk;

  /// 诊断用：申请次数。
  int get activateCount => _activateCount;

  /// 诊断用：是否处于「因打断而暂停、等打断结束自动恢复」的等待中。
  bool get interruptedWhilePlaying => _interruptedWhilePlaying;

  /// 配置音频会话并挂上焦点事件监听。幂等；失败只打调试日志——焦点补偿缺席
  /// 只让打断场景退化为「不停播」，不影响播放本身。
  Future<void> initialize() async {
    if (_configured) return;
    _configured = true;
    // 先挂状态监听再等 session：保证 configure 完成前发生的播放态变化
    // （恢复上次会话的自动播放）也不会漏掉焦点申请。
    _coordinator.playerState.addListener(_onPlayerStateChanged);
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSub = session.interruptionEventStream.listen(
        _onInterruption,
      );
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        debugPrint('[AudioFocusService] 拔出耳机（audio becoming noisy），暂停播放');
        unawaited(_coordinator.pause());
      });
    } catch (e) {
      debugPrint('[AudioFocusService] 音频会话初始化失败（焦点补偿缺席）: $e');
    }
  }

  /// 打断事件 → 暂停 / 恢复。与 just_audio 的 handleInterruptions 逐分支对齐。
  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // media usage 不压音量、不暂停（just_audio 仅对 game 减半音量）。
          _interruptedWhilePlaying = false;
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_coordinator.isPlaying) {
            debugPrint('[AudioFocusService] 音频被打断(${event.type.name})，暂停播放');
            // 不 await：标记在本同步段写完，先于 pause 引发的任何状态回调
            // （just_audio 同款处理，见其源码注释 "done in the sync portion"）。
            unawaited(_coordinator.pause());
            _interruptedWhilePlaying = true;
          }
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _interruptedWhilePlaying = false;
          break;
        case AudioInterruptionType.pause:
          if (_interruptedWhilePlaying) {
            debugPrint('[AudioFocusService] 打断结束，恢复播放');
            unawaited(_coordinator.resume());
          }
          _interruptedWhilePlaying = false;
          break;
        case AudioInterruptionType.unknown:
          // 永久失去焦点（AUDIOFOCUS_LOSS）：不自动恢复。
          _interruptedWhilePlaying = false;
          break;
      }
    }
  }

  /// 播放态观察：
  /// - 进入播放态 → 清「因打断而暂停」标记，
  ///   并申请焦点（对齐其 handleAudioSessionActivation：play 时 setActive）；
  /// - 进入 Idle / Completed（stop 语义）→ 清标记。
  /// PlayerPlaying(fadeCountdown) → PlayerPlaying() 的 fade 子态切换不算
  /// 进入播放态（`_wasPlaying` 挡住），crossfade 全程只申请一次。
  void _onPlayerStateChanged() {
    final state = _coordinator.playerState.value;
    final playing = state is PlayerPlaying;
    if (playing && !_wasPlaying) {
      _interruptedWhilePlaying = false;
      unawaited(activate());
    } else if (!playing && (state is PlayerIdle || state is PlayerCompleted)) {
      _interruptedWhilePlaying = false;
    }
    _wasPlaying = playing;
  }

  /// 申请音频焦点。Android 侧 setActive(true) 即 requestAudioFocus；重复调用安全。
  Future<void> activate() async {
    _activateCount++;
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      _lastActivateOk = true;
    } catch (e) {
      _lastActivateOk = false;
      debugPrint('[AudioFocusService] 申请音频焦点失败: $e');
    }
  }

  /// 释放监听。
  Future<void> dispose() async {
    _coordinator.playerState.removeListener(_onPlayerStateChanged);
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    _interruptionSub = null;
    _becomingNoisySub = null;
  }
}
