import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:rxdart/rxdart.dart';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/models/player_state.dart';

/// 播放器角色枚举
enum PlayerRole {
  active, // 当前正在播放的活跃播放器
  standby, // 预加载下一首的待命播放器
}

/// 播放器状态信息
class PlayerStateInfo {
  final ja.AudioPlayer player;
  PlayerRole role;
  double volume;
  String? currentUrl;
  bool isReady;

  PlayerStateInfo({
    required this.player,
    this.role = PlayerRole.standby,
    this.volume = 1.0,
    this.currentUrl,
    this.isReady = false,
  });

  /// 重置播放器状态
  void reset() {
    volume = 1.0;
    currentUrl = null;
    isReady = false;
  }
}

/// 双播放器音频服务
/// 管理两个AudioPlayer实例交替工作,实现真正的交叉淡入淡出
class DualAudioService {
  // 两个播放器实例(使用late延迟初始化)
  late PlayerStateInfo _playerA;
  late PlayerStateInfo _playerB;

  // 统一状态机：替代原 _state / CrossfadeState / _isPreloading / _isCrossfading 三件套
  final ValueNotifier<PlayerState> _playerState = ValueNotifier(PlayerIdle());
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<PlayMode> _playMode = ValueNotifier(PlayMode.sequential);

  final double _standbyVolume = 0.3; // 待命播放器的初始音量，避免进入mute状态
  final int _audioTrackStartupDelay = 100; // 音频轨道启动的额外延迟，确保音量调整生效

  // 订阅管理
  final List<StreamSubscription> _subscriptions = [];

  // 回调函数
  Function()? onPlaybackCompleted;
  Function(Duration)? onPositionChanged;
  Function(AudioState)? onStateChanged;

  DualAudioService();

  /// 初始化两个播放器实例
  void initialize() {
    _playerA = PlayerStateInfo(player: ja.AudioPlayer(), role: PlayerRole.active);
    _playerB = PlayerStateInfo(player: ja.AudioPlayer(), role: PlayerRole.standby);

    _setupPlayerListeners(_playerA);
    _setupPlayerListeners(_playerB);

    debugPrint('[DualAudioService] 双播放器初始化完成');
  }

  /// 获取活跃播放器引用
  PlayerStateInfo get _activePlayer {
    return _playerA.role == PlayerRole.active ? _playerA : _playerB;
  }

  /// 获取待命播放器引用
  PlayerStateInfo get _standbyPlayer {
    return _playerA.role == PlayerRole.standby ? _playerA : _playerB;
  }

  /// 为播放器设置监听器
  void _setupPlayerListeners(PlayerStateInfo playerInfo) {
    // 监听播放状态
    final stateSub = playerInfo.player.playerStateStream.listen((state) {
      _handlePlayerStateChange(playerInfo, state);
    });

    // 监听播放位置(使用节流减少更新频率)
    final positionSub = playerInfo.player.positionStream
        .transform(
          ThrottleStreamTransformer<Duration>(
            (_) => Stream<Duration>.periodic(
              const Duration(milliseconds: 200),
              (_) => Duration.zero,
            ),
          ),
        )
        .listen((position) {
          if (playerInfo.role == PlayerRole.active) {
            _position.value = position;
            onPositionChanged?.call(position);
          }
        });

    // 监听时长变化
    final durationSub = playerInfo.player.durationStream.listen((duration) {
      if (duration != null && playerInfo.role == PlayerRole.active) {
        _duration.value = duration;
      }
    });

    _subscriptions.addAll([stateSub, positionSub, durationSub]);
  }

  /// 处理播放器状态变化
  void _handlePlayerStateChange(PlayerStateInfo playerInfo, ja.PlayerState state) {
    final processingState = state.processingState;
    final isPlaying = state.playing;

    // 检测播放完成
    if (processingState == ja.ProcessingState.completed &&
        playerInfo.role == PlayerRole.active) {
      debugPrint('[DualAudioService] 检测到播放完成');
      _playerState.value = PlayerCompleted();
      onPlaybackCompleted?.call();
      return;
    }

    // 更新内部状态(只报告活跃播放器的状态)
    if (playerInfo.role == PlayerRole.active) {
      AudioState newState;
      if (processingState == ja.ProcessingState.completed) {
        newState = AudioState.stopped;
      } else if (processingState == ja.ProcessingState.buffering ||
          processingState == ja.ProcessingState.loading) {
        newState = AudioState.buffering;
      } else if (processingState == ja.ProcessingState.ready ||
          processingState == ja.ProcessingState.idle) {
        // ready或idle状态下，根据isPlaying判断
        newState = isPlaying ? AudioState.playing : AudioState.paused;
      } else {
        // 其他状态（如idle）
        newState = isPlaying ? AudioState.playing : AudioState.paused;
      }

      // 只在状态真正改变时才更新，避免不必要的通知
      if (_audioStateOf(_playerState.value) != newState) {
        debugPrint(
          '[DualAudioService] 状态变更 ${_audioStateOf(_playerState.value)} -> $newState (processing=$processingState, playing=$isPlaying)',
        );
        _syncPlayerStateFromAudio(newState);
        onStateChanged?.call(newState);
      }
    }
  }

  /// 从 just_audio 的 AudioState 推导 PlayerState，保留 fadeCountdown
  void _syncPlayerStateFromAudio(AudioState audioState) {
    final current = _playerState.value;
    final fadeCountdown = current is PlayerPlaying ? current.fadeCountdown : null;

    switch (audioState) {
      case AudioState.playing:
        _playerState.value = PlayerPlaying(fadeCountdown: fadeCountdown);
        break;
      case AudioState.paused:
        _playerState.value = PlayerPaused();
        break;
      case AudioState.buffering:
        _playerState.value = PlayerBuffering();
        break;
      case AudioState.stopped:
        _playerState.value = PlayerIdle();
        break;
    }
  }

  /// 从 PlayerState 提取 AudioState 等价值（仅用于日志/旧回调）
  static AudioState _audioStateOf(PlayerState state) {
    return switch (state) {
      PlayerIdle _ => AudioState.stopped,
      PlayerBuffering _ => AudioState.buffering,
      PlayerPlaying _ => AudioState.playing,
      PlayerPaused _ => AudioState.paused,
      PlayerCompleted _ => AudioState.stopped,
    };
  }

  // ============ 公开API ============

  /// 获取活跃播放器
  ja.AudioPlayer get activePlayer => _activePlayer.player;

  /// 获取待命播放器
  ja.AudioPlayer get standbyPlayer => _standbyPlayer.player;

  /// 获取当前播放状态（PlayerState sealed class 单一状态机）
  ValueListenable<PlayerState> get playerState => _playerState;

  /// 旧 AudioState 派生（仅给 BaseAudioHandler / 旧 UI 兜底用）
  AudioState get currentAudioState => _audioStateOf(_playerState.value);

  /// 获取当前播放位置
  ValueNotifier<Duration> get position => _position;

  /// 获取当前音频时长
  ValueNotifier<Duration> get duration => _duration;

  /// 获取当前播放模式
  ValueNotifier<PlayMode> get playMode => _playMode;

  /// 获取是否正在播放
  bool get isPlaying => _activePlayer.player.playing;

  /// 获取当前播放位置(同步)
  Duration get currentPosition => _activePlayer.player.position;

  /// 获取当前音频时长(同步)
  Duration get currentDuration =>
      _activePlayer.player.duration ?? Duration.zero;

  /// 获取播放进度百分比
  double get progressPercentage {
    final dur = _activePlayer.player.duration;
    if (dur == null || dur.inMilliseconds == 0) {
      return 0.0;
    }
    return _activePlayer.player.position.inMilliseconds / dur.inMilliseconds;
  }

  /// 是否处于淡入淡出中（替代旧 isCrossfading + crossfadeState）
  bool get isFading => _playerState.value is PlayerPlaying &&
      (_playerState.value as PlayerPlaying).fadeCountdown != null;

  /// 检查待命播放器是否就绪
  bool get isStandbyReady => _standbyPlayer.isReady;

  /// 写状态机：替代 setPreloading + 直接赋值 crossfadeState/_isCrossfading
  void setPlayerState(PlayerState state) {
    _playerState.value = state;
  }

  // ============ 播放控制方法 ============

  /// 使用活跃播放器播放URL
  Future<void> playActive(String url) async {
    try {
      debugPrint('[DualAudioService] 开始播放 $url');
      _playerState.value = PlayerBuffering();
      await _activePlayer.player.setUrl(url);
      await _activePlayer.player.seek(Duration.zero);
      await _activePlayer.player.setVolume(1.0);
      _activePlayer.volume = 1.0;
      _activePlayer.currentUrl = url;
      _activePlayer.isReady = true;
      await _activePlayer.player.play();
      // 注意：不立即设置_playerState为playing，让播放器状态监听器来更新状态
      debugPrint('[DualAudioService] 播放命令已发送');
    } catch (e) {
      debugPrint('[DualAudioService] 播放失败 $e');
      _playerState.value = PlayerIdle();
      rethrow;
    }
  }

  /// 预加载音频到待命播放器
  Future<void> preloadToStandby(String url) async {
    try {
      debugPrint('[DualAudioService] 开始预加载 $url');
      // 注意：不要修改_playerState，因为这是standby播放器，不应该影响UI显示的active状态

      await _standbyPlayer.player.setUrl(url);
      _standbyPlayer.currentUrl = url;
      _standbyPlayer.isReady = true;
      // 不在这里设置音量为0.0，避免AudioTrack进入长时间mute状态
      // 音量将在executeCrossfade时设置

      debugPrint('[DualAudioService] 预加载完成');
    } catch (e) {
      debugPrint('[DualAudioService] 预加载失败 $e');
      _standbyPlayer.isReady = false;
      rethrow;
    }
  }

  /// 执行交叉淡入淡出切换（编排：_primeStandby → swap → fade curve → finalize）
  Future<void> executeCrossfade(int durationMs) async {
    if (isFading) {
      debugPrint('[DualAudioService] Crossfade已在进行中,跳过');
      return;
    }

    if (!_standbyPlayer.isReady) {
      debugPrint('[DualAudioService] 待命播放器未就绪,无法执行crossfade');
      throw Exception('Standby player not ready');
    }

    debugPrint('[DualAudioService] 开始Crossfade,时长${durationMs}ms');

    try {
      await _primeStandby();
      // 立即交换角色，让 UI 切到新 active
      _swapPlayers();

      // 延长延迟确保AudioTrack完全启动
      await Future.delayed(Duration(milliseconds: _audioTrackStartupDelay));

      await _performFadeCurve(durationMs);
      await _finalizeSwap();
    } catch (e) {
      debugPrint('[DualAudioService] Crossfade失败 $e');
      await _recoverFromCrossfadeError();
      rethrow;
    } finally {
      // fade 结束时清掉 fadeCountdown，但保留 Playing/Paused 本身
      final cur = _playerState.value;
      if (cur is PlayerPlaying) {
        _playerState.value = PlayerPlaying();
      }
    }
  }

  /// Step 1：准备待命播放器（音量 + seek + play）。
  /// 音量故意给到 `_standbyVolume`（非 0），避免 AudioTrack 进入长时间 mute。
  Future<void> _primeStandby() async {
    await _standbyPlayer.player.setVolume(_standbyVolume);
    _standbyPlayer.volume = _standbyVolume;
    await _standbyPlayer.player.seek(Duration.zero);

    // 我不知道just_audio和media_kit是怎么协调的
    // 这里不能使用异步 await , just_audio的实现会阻塞代码进行
    // 但是media_kit的实现不会阻塞代码进行, 神金
    // 你们两个库都给我飞起来
    _standbyPlayer.player.play();
  }

  /// Step 3：分 20 步同步调整 active/standby 音量，支持超时 + pause 中断。
  Future<void> _performFadeCurve(int durationMs) async {
    const steps = 20;
    final stepDuration = Duration(milliseconds: durationMs ~/ steps);

    // 标记进入 fading 子态（Coordinator 会持续更新 fadeCountdown）
    _playerState.value = PlayerPlaying(fadeCountdown: (durationMs / 1000).ceil());

    // 超时保护
    final timeoutTimer = Timer(
      Duration(milliseconds: durationMs + 2000),
      () => debugPrint('[DualAudioService] Crossfade超时，强制完成'),
    );

    for (int i = 0; i <= steps; i++) {
      final progress = i / steps;

      // Standby播放器淡出: 1.0 → 0.0（允许到0）
      final standbyVolume = 1.0 - progress;
      await _standbyPlayer.player.setVolume(standbyVolume);
      _standbyPlayer.volume = standbyVolume;

      // Active 播放器淡入: 0.0 → 1.0（从0开始）
      final activeVolume = progress;
      await _activePlayer.player.setVolume(activeVolume);
      _activePlayer.volume = activeVolume;

      await Future.delayed(stepDuration);

      // 检查被 pause 中断（pause() 会把状态切到 PlayerPaused）
      if (_playerState.value is PlayerPaused) {
        debugPrint('[DualAudioService] Crossfade被暂停中断');
        break;
      }
    }

    timeoutTimer.cancel();
  }

  /// Step 4-6：fade 完成后把 active 音量拉满、停止旧 active、归位 standby。
  Future<void> _finalizeSwap() async {
    // 把当前 active（原 standby）音量恢复满
    await _activePlayer.player.setVolume(1.0);
    _activePlayer.volume = 1.0;

    // 确保新 active 仍在播放
    if (!_activePlayer.player.playing) {
      debugPrint('[DualAudioService] 新active播放器未播放，重新启动');
      await _activePlayer.player.play();
    }

    // 停止原 active（现在角色是 standby）
    await Future.delayed(const Duration(milliseconds: 100));
    await _standbyPlayer.player.stop();
    await _standbyPlayer.player.seek(Duration.zero);
    _standbyPlayer.reset();

    debugPrint('[DualAudioService] Crossfade完成,角色已交换');
  }

  /// 交换活跃/待命角色
  void _swapPlayers() {
    if (_playerA.role == PlayerRole.active) {
      _playerA.role = PlayerRole.standby;
      _playerB.role = PlayerRole.active;
    } else {
      _playerB.role = PlayerRole.standby;
      _playerA.role = PlayerRole.active;
    }
    debugPrint('[DualAudioService] 播放器角色已交换');
  }

  /// 从Crossfade错误中恢复
  Future<void> _recoverFromCrossfadeError() async {
    debugPrint('[DualAudioService] 从Crossfade错误中恢复');

    // 确保至少有一个播放器在播放
    if (!_activePlayer.player.playing && _standbyPlayer.player.playing) {
      _swapPlayers();
      await _activePlayer.player.setVolume(1.0);
      await _standbyPlayer.player.stop();
    } else if (!_standbyPlayer.player.playing) {
      await stop();
    }

    if (_playerState.value is PlayerPlaying) {
      _playerState.value = PlayerPlaying();
    } else {
      _playerState.value = PlayerIdle();
    }
  }

  /// 取消crossfade并准备播放新歌曲
  /// 如果url为null，则只取消crossfade状态，不播放新歌曲
  Future<void> cancelAndPlay(String? url) async {
    // 清掉 fade 子态
    if (_playerState.value is PlayerPlaying) {
      _playerState.value = PlayerPlaying();
    }

    // 清空待命播放器
    await _standbyPlayer.player.stop();
    await _standbyPlayer.player.seek(Duration.zero);
    await _standbyPlayer.player.setVolume(1.0); // 重置音量为1.0，避免下次启动时状态异常
    _standbyPlayer.reset();

    // 如果提供了URL，则播放新歌曲
    if (url != null) {
      await playActive(url);
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    if (isFading) {
      // fade 中断：把状态切到 Paused，_performFadeCurve 会自己跳出
      _playerState.value = PlayerPaused();
      debugPrint('[DualAudioService] Crossfade中暂停');
    } else {
      await _activePlayer.player.pause();
    }
    // 不在这里手动设置状态，让 playerStateStream 监听器自动处理
    // 这样可以避免手动设置与监听器回调之间的竞态条件
  }

  /// 恢复播放
  Future<void> resume() async {
    await _activePlayer.player.play();

    // 确保音量为1.0
    await _activePlayer.player.setVolume(1.0);
    _activePlayer.volume = 1.0;

    // 不在这里手动设置状态，让 playerStateStream 监听器自动处理
  }

  /// 停止播放
  Future<void> stop() async {
    await _activePlayer.player.stop();
    await _standbyPlayer.player.stop();
    await _standbyPlayer.player.seek(Duration.zero);
    _activePlayer.reset();
    _standbyPlayer.reset();
    _playerState.value = PlayerIdle();
    onStateChanged?.call(AudioState.stopped);
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _activePlayer.player.seek(position);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final currentIndex = _playMode.value.index;
    final nextIndex = (currentIndex + 1) % PlayMode.values.length;
    _playMode.value = PlayMode.values[nextIndex];
    debugPrint('[DualAudioService] 播放模式切换为 ${_playMode.value}');
  }

  /// 释放资源
  Future<void> dispose() async {
    debugPrint('[DualAudioService] 开始释放资源');

    // 取消所有订阅
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    // 停止并释放两个播放器
    await _playerA.player.stop();
    await _playerA.player.dispose();
    await _playerB.player.stop();
    await _playerB.player.dispose();

    debugPrint('[DualAudioService] 资源释放完成');
  }
}