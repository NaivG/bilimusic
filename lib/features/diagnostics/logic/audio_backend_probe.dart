import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/domain/play_mode.dart';
import 'package:bilimusic/features/player/logic/audio_focus_service.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/logic/notification_service.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/player/models/player_state.dart';

/// 测试页的一行键值。
@immutable
class DiagnosticRow {
  const DiagnosticRow(this.label, this.value, {this.warn = false, this.ok});

  final String label;
  final String value;

  /// 普通信息行：true 表示这一项看着不对（测试页染成 error 色）。
  final bool warn;

  /// 自检行：null = 非自检行；true / false = ✓ / ✗。
  final bool? ok;
}

/// 单个播放器（A / B）的引擎侧快照。
///
/// `info` 是我们自己的账（角色 / 待命就绪门 / 当前 URL），`state` 是 mpv 的
/// **同步状态快照**（包里保证快照先于流事件更新，所以采到的是一致的一帧）。
@immutable
class PlayerEngineSnapshot {
  const PlayerEngineSnapshot({
    required this.label,
    required this.info,
    required this.state,
  });

  final String label;
  final PlayerStateInfo info;
  final mpv.PlayerState state;

  String get roleLabel =>
      info.role == PlayerRole.active ? 'active · 出声' : 'standby · 待命';

  /// 引擎侧的"要不要播"（意图轴）。
  bool get playWhenReady => state.playWhenReady;

  /// 引擎侧的"有没有真的出声"（seek / 缓冲期间会瞬抖）。
  bool get playing => state.playing;

  bool get buffering => state.buffering || state.pausedForCache;

  /// 已装载（`open` 之后 duration 落到非零）。
  bool get hasMedia => state.duration > Duration.zero;

  List<DiagnosticRow> get rows => [
    DiagnosticRow('角色', roleLabel),
    // 意图关了但还在出声 = 真的不一致（seek / 缓冲期间 intent 与 output 短暂
    // 不同步是正常的，只有这个方向才说明暂停没落地）。
    DiagnosticRow(
      '意图 playWhenReady',
      '${state.playWhenReady}',
      warn: !state.playWhenReady && state.playing,
    ),
    DiagnosticRow('出声 playing', '${state.playing}'),
    DiagnosticRow(
      '装载缓冲 buffering',
      '${state.buffering}',
      warn: state.buffering,
    ),
    DiagnosticRow(
      '中途卡顿 pausedForCache',
      '${state.pausedForCache}',
      warn: state.pausedForCache,
    ),
    DiagnosticRow('自然结束 completed', '${state.completed}'),
    DiagnosticRow(
      '位置 / 时长',
      '${_fmt(state.position)} / ${_fmt(state.duration)}',
    ),
    DiagnosticRow('已缓冲到', _fmt(state.buffer)),
    DiagnosticRow('音量（mpv 0-100）', state.volume.toStringAsFixed(1)),
    DiagnosticRow('静音 mute', '${state.mute}'),
    DiagnosticRow(
      '待命就绪门 isReady',
      '${info.isReady}',
      warn:
          info.role == PlayerRole.standby &&
          info.currentUrl != null &&
          !info.isReady,
    ),
    DiagnosticRow('当前源', info.currentUrl ?? '（未装载）'),
    DiagnosticRow('path', state.path.isEmpty ? '（空）' : state.path),
    DiagnosticRow('媒体标题', state.mediaTitle.isEmpty ? '（空）' : state.mediaTitle),
    DiagnosticRow('音频驱动', '${state.audioDriver} · ${state.audioOutputState}'),
  ];
}

/// 音频后端的一帧完整快照：引擎 + 应用状态机 + 媒体会话 + 音频焦点。
@immutable
class AudioBackendSnapshot {
  const AudioBackendSnapshot({
    required this.players,
    required this.appRows,
    required this.sessionRows,
    required this.focusRows,
    required this.selfCheck,
    required this.reportedState,
  });

  final List<PlayerEngineSnapshot> players;
  final List<DiagnosticRow> appRows;
  final List<DiagnosticRow> sessionRows;
  final List<DiagnosticRow> focusRows;

  /// 我们最后一次上报给系统媒体会话的 PlaybackState（null = 还没上报过）。
  /// **系统对耳机键的方向判定看的就是它**，所以单独留一份原样数据。
  final PlaybackState? reportedState;

  /// 自检行（✓ / ✗）——"后端状态"的直接结论。
  final List<DiagnosticRow> selfCheck;

  int get anomalyCount => selfCheck.where((r) => r.ok == false).length;

  /// 引擎版本串（mpv / ffmpeg）。
  String get engineVersion {
    for (final p in players) {
      if (p.state.mpvVersion.isNotEmpty) {
        return 'libmpv ${p.state.mpvVersion} · ${p.state.ffmpegVersion}';
      }
    }
    return '（未上报版本）';
  }
}

/// 音频后端测试页的采集器（只读，不改任何播放状态）。
class AudioBackendProbe {
  AudioBackendProbe({
    required PlayerCoordinator coordinator,
    required DualAudioService dualAudio,
    required NotificationService notifications,
    required AudioFocusService audioFocus,
  }) : _coordinator = coordinator,
       _dual = dualAudio,
       _notifications = notifications,
       _audioFocus = audioFocus;

  final PlayerCoordinator _coordinator;
  final DualAudioService _dual;
  final NotificationService _notifications;
  final AudioFocusService _audioFocus;

  /// 采集一帧。
  AudioBackendSnapshot capture() {
    final players = [
      PlayerEngineSnapshot(
        label: 'A',
        info: _dual.activePlayerInfo,
        state: _dual.activePlayerInfo.player.state,
      ),
      PlayerEngineSnapshot(
        label: 'B',
        info: _dual.standbyPlayerInfo,
        state: _dual.standbyPlayerInfo.player.state,
      ),
    ];
    // A/B 的角色是互斥的，`activePlayerInfo` 只命中一个；用标签兜住"哪个是
    // 当前出声的那台"，页面上一眼能看出来。
    final active = players.firstWhere(
      (p) => p.info.role == PlayerRole.active,
      orElse: () => players.first,
    );

    final reported = _notifications.lastPlaybackState;
    final intent = _dual.isPlaying;
    final state = _dual.playerState.value;

    return AudioBackendSnapshot(
      players: players,
      appRows: [
        DiagnosticRow('状态机', _stateLabel(state)),
        DiagnosticRow('意图轴 isPlaying', '$intent'),
        DiagnosticRow('实际出声', '${active.playing}'),
        DiagnosticRow('crossfade 中', '${_dual.isFading}'),
        DiagnosticRow('待命就绪 isStandbyReady', '${_dual.isStandbyReady}'),
        DiagnosticRow(
          '用户音量 / 相对比率',
          '${_dual.volume.value.toStringAsFixed(2)} × '
              '${_dual.relativeVolume.toStringAsFixed(2)} '
              '= ${_dual.effectiveVolume.toStringAsFixed(2)}',
        ),
        DiagnosticRow(
          '实际音质',
          _dual.actualQualityId.value.isEmpty
              ? '（尚未取流）'
              : _dual.actualQualityId.value,
        ),
        DiagnosticRow('当前曲目', _coordinator.currentMusic?.title ?? '（无）'),
        DiagnosticRow('播放模式', _dual.playMode.value.name),
      ],
      sessionRows: [
        DiagnosticRow(
          'playing（上报值）',
          reported == null ? '（还没上报过）' : '${reported.playing}',
          warn: reported != null && reported.playing != intent,
        ),
        DiagnosticRow(
          'processingState',
          reported == null ? '—' : reported.processingState.name,
        ),
        DiagnosticRow(
          'updatePosition / bufferedPosition',
          reported == null
              ? '—'
              : '${_fmt(reported.updatePosition)} / '
                    '${_fmt(reported.bufferedPosition)}',
        ),
        DiagnosticRow('speed', reported == null ? '—' : '${reported.speed}'),
        DiagnosticRow(
          '控件',
          reported == null || reported.controls.isEmpty
              ? '（空）'
              : reported.controls.map(_controlLabel).join(' · '),
          warn: reported != null && reported.controls.isEmpty,
        ),
        DiagnosticRow('上报次数', '${_notifications.playbackStatePushCount}'),
        DiagnosticRow('通知曲目', _notifications.lastMediaItem?.title ?? '（还没上报过）'),
      ],
      focusRows: [
        DiagnosticRow(
          'audio_session 已配置',
          '${_audioFocus.isConfigured}',
          warn: !_audioFocus.isConfigured,
        ),
        DiagnosticRow('最近一次 setActive', switch (_audioFocus.lastActivateOk) {
          null => '（还没申请过）',
          true => '成功（已持有焦点）',
          false => '失败',
        }, warn: _audioFocus.lastActivateOk == false),
        DiagnosticRow('申请次数', '${_audioFocus.activateCount}'),
        DiagnosticRow('「因打断而暂停」待恢复', '${_audioFocus.interruptedWhilePlaying}'),
      ],
      selfCheck: _selfCheck(players, active, reported, intent),
      reportedState: reported,
    );
  }

  List<DiagnosticRow> _selfCheck(
    List<PlayerEngineSnapshot> players,
    PlayerEngineSnapshot active,
    PlaybackState? reported,
    bool intent,
  ) {
    // 「还没开始播」不是异常：这类自检行给 ok=null（中性），页面显示 `·`。
    // 只有"应用以为在播/暂停、引擎却没装载"或"上报与意图不一致"才是 ✗。
    // crossfade 窗口内的两路同播是设计行为，不算打架（见 twoPlayersFightCheck）。
    final mediaExpected = _dual.currentAudioState != AudioState.stopped;
    final rows = <DiagnosticRow>[
      DiagnosticRow(
        '引擎已装载当前曲目',
        active.hasMedia ? _fmt(active.state.duration) : '未装载',
        ok: active.hasMedia ? true : (mediaExpected ? false : null),
      ),
      DiagnosticRow(
        '上报 playing 与引擎意图一致',
        reported == null ? '还没上报过' : '上报 ${reported.playing} / 意图 $intent',
        ok: _reportedMatchesIntent(reported, intent),
      ),
      DiagnosticRow(
        '媒体会话有控件',
        reported == null
            ? '还没上报过'
            : (reported.controls.isEmpty
                  ? '空'
                  : '${reported.controls.length} 个'),
        ok: reported?.controls.isNotEmpty,
      ),
      DiagnosticRow(
        '音频焦点服务已就绪',
        _audioFocus.isConfigured ? '是' : '否（打断/拔耳机不会暂停）',
        ok: _audioFocus.isConfigured,
      ),
      DiagnosticRow(
        '无中途卡顿',
        active.state.pausedForCache ? 'pausedForCache' : '正常',
        ok: !active.state.pausedForCache,
      ),
      twoPlayersFightCheck(
        playerAPlayWhenReady: players[0].state.playWhenReady,
        playerBPlayWhenReady: players[1].state.playWhenReady,
        isFading: _dual.isFading,
        relativeVolume: _dual.relativeVolume,
      ),
    ];
    return rows;
  }

  /// 「两路播放器不打架」自检行。
  ///
  /// crossfade 期间两路播放器被**设计为同时出声**（旧曲淡出、新曲淡入），
  /// 不能只凭"两路 playWhenReady 同时为 true"就判打架，还要看是否处于
  /// 淡入淡出窗口。窗口判定取两个信号的并集，分别盖住状态机标记前后的
  /// 两条缝隙：
  /// - `isFading`（fadeCountdown 已置位）：fade 曲线推进中——以及 fade 已
  ///   走完、正在收尾（停旧曲）的那一小段，此刻相对音量已回到 1.0；
  /// - `relativeVolume < 1.0`：fade 机构已接管（_primeStandby 先把相对音量
  ///   归零、两路开始同播）但 fadeCountdown 尚未置位的窗口；fade 中途撞上
  ///   缓冲把状态机挤出 PlayerPlaying 时也靠它兜住。
  @visibleForTesting
  static DiagnosticRow twoPlayersFightCheck({
    required bool playerAPlayWhenReady,
    required bool playerBPlayWhenReady,
    required bool isFading,
    required double relativeVolume,
  }) {
    final bothPlaying = playerAPlayWhenReady && playerBPlayWhenReady;
    final inFadeWindow = isFading || relativeVolume < 1.0;
    return DiagnosticRow(
      '两路播放器不打架',
      bothPlaying
          ? (inFadeWindow ? 'A=true B=true · crossfade 中' : 'A=true B=true')
          : 'A=$playerAPlayWhenReady B=$playerBPlayWhenReady',
      ok: !bothPlaying || inFadeWindow,
    );
  }

  /// 「上报给系统的 playing」与引擎意图是否一致。还没上报过时返回 null
  /// （中性，不算异常）——冷启动时系统会话里本来就还没有状态。
  static bool? _reportedMatchesIntent(PlaybackState? reported, bool intent) {
    if (reported == null) return null;
    return reported.playing == intent;
  }

  static String _stateLabel(PlayerState state) => switch (state) {
    PlayerIdle() => 'PlayerIdle（空闲）',
    PlayerBuffering() => 'PlayerBuffering（装载/卡顿）',
    PlayerPlaying(:final fadeCountdown) =>
      fadeCountdown == null
          ? 'PlayerPlaying（稳定播放）'
          : 'PlayerPlaying（crossfade 倒计时 $fadeCountdown）',
    PlayerPaused() => 'PlayerPaused（暂停）',
    PlayerCompleted() => 'PlayerCompleted（播完）',
  };

  static String _controlLabel(MediaControl control) =>
      control.label.isEmpty ? control.action.name : control.label;
}

/// `1:03.482` 形态；零值显示 `0:00.000`。
String _fmt(Duration d) {
  final sign = d.isNegative ? '-' : '';
  final abs = d.abs();
  final m = abs.inMinutes;
  final s = abs.inSeconds % 60;
  final ms = abs.inMilliseconds % 1000;
  return '$sign$m:${s.toString().padLeft(2, '0')}'
      '.${ms.toString().padLeft(3, '0')}';
}
