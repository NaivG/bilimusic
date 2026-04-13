import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:bilimusic/managers/player_manager.dart';

/// 播放器角色枚举
enum PlayerRole {
  active, // 当前正在播放的活跃播放器
  standby, // 预加载下一首的待命播放器
}

/// 交叉淡入淡出状态
enum CrossfadeState {
  idle, // 空闲
  preloading, // 预加载中
  fading, // 淡入淡出进行中
  completed, // 切换完成
}

/// 播放器状态信息
class PlayerStateInfo {
  final AudioPlayer player;
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

  // 交叉淡入淡出状态
  final ValueNotifier<CrossfadeState> _crossfadeState = ValueNotifier(
    CrossfadeState.idle,
  );
  final ValueNotifier<AudioState> _state = ValueNotifier(AudioState.stopped);
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<PlayMode> _playMode = ValueNotifier(PlayMode.sequential);

  // 订阅管理
  final List<StreamSubscription> _subscriptions = [];

  // 防抖标志
  bool _isPreloading = false;
  bool _isCrossfading = false;

  // 回调函数
  Function()? onPlaybackCompleted;
  Function(Duration)? onPositionChanged;
  Function(AudioState)? onStateChanged;

  DualAudioService();

  /// 初始化两个播放器实例
  void initialize() {
    _playerA = PlayerStateInfo(player: AudioPlayer(), role: PlayerRole.active);
    _playerB = PlayerStateInfo(player: AudioPlayer(), role: PlayerRole.standby);

    _setupPlayerListeners(_playerA);
    _setupPlayerListeners(_playerB);

    debugPrint('DualAudioService: 双播放器初始化完成');
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
  void _handlePlayerStateChange(PlayerStateInfo playerInfo, PlayerState state) {
    final processingState = state.processingState;
    final isPlaying = state.playing;

    // 检测播放完成
    if (processingState == ProcessingState.completed &&
        playerInfo.role == PlayerRole.active) {
      debugPrint('DualAudioService: 检测到播放完成');
      onPlaybackCompleted?.call();
      return;
    }

    // 更新内部状态(只报告活跃播放器的状态)
    if (playerInfo.role == PlayerRole.active) {
      AudioState newState;
      if (processingState == ProcessingState.completed) {
        newState = AudioState.stopped;
      } else if (processingState == ProcessingState.buffering ||
          processingState == ProcessingState.loading) {
        newState = AudioState.buffering;
      } else if (processingState == ProcessingState.ready ||
          processingState == ProcessingState.idle) {
        // ready或idle状态下，根据isPlaying判断
        newState = isPlaying ? AudioState.playing : AudioState.paused;
      } else {
        // 其他状态（如idle）
        newState = isPlaying ? AudioState.playing : AudioState.paused;
      }

      // 只在状态真正改变时才更新，避免不必要的通知
      if (_state.value != newState) {
        debugPrint(
          'DualAudioService: 状态变更 ${_state.value} -> $newState (processing=$processingState, playing=$isPlaying)',
        );
        _state.value = newState;
        onStateChanged?.call(newState);
      }
    }
  }

  // ============ 公开API ============

  /// 获取活跃播放器
  AudioPlayer get activePlayer => _activePlayer.player;

  /// 获取待命播放器
  AudioPlayer get standbyPlayer => _standbyPlayer.player;

  /// 获取当前播放状态
  ValueNotifier<AudioState> get state => _state;

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

  /// 获取交叉淡入淡出状态
  ValueNotifier<CrossfadeState> get crossfadeState => _crossfadeState;

  /// 检查是否正在预加载
  bool get isPreloading => _isPreloading;

  /// 检查是否正在crossfade
  bool get isCrossfading => _isCrossfading;

  /// 检查待命播放器是否就绪
  bool get isStandbyReady => _standbyPlayer.isReady;

  /// 设置预加载状态
  void setPreloading(bool value) {
    _isPreloading = value;
    if (value) {
      _crossfadeState.value = CrossfadeState.preloading;
    }
  }

  // ============ 播放控制方法 ============

  /// 使用活跃播放器播放URL
  Future<void> playActive(String url) async {
    try {
      debugPrint('DualAudioService: 开始播放 $url');
      _state.value = AudioState.buffering;
      await _activePlayer.player.setUrl(url);
      await _activePlayer.player.seek(Duration.zero);
      await _activePlayer.player.setVolume(1.0);
      _activePlayer.volume = 1.0;
      _activePlayer.currentUrl = url;
      _activePlayer.isReady = true;
      await _activePlayer.player.play();
      // 注意：不立即设置_state为playing，让播放器状态监听器来更新状态
      debugPrint('DualAudioService: 播放命令已发送');
    } catch (e) {
      debugPrint('DualAudioService: 播放失败 $e');
      _state.value = AudioState.stopped;
      rethrow;
    }
  }

  /// 预加载音频到待命播放器
  Future<void> preloadToStandby(String url) async {
    try {
      debugPrint('DualAudioService: 开始预加载 $url');
      // 注意：不要修改_state，因为这是standby播放器，不应该影响UI显示的active状态

      await _standbyPlayer.player.setUrl(url);
      _standbyPlayer.currentUrl = url;
      _standbyPlayer.isReady = true;
      // 不在这里设置音量为0.0，避免AudioTrack进入长时间mute状态
      // 音量将在executeCrossfade时设置

      debugPrint('DualAudioService: 预加载完成');
    } catch (e) {
      debugPrint('DualAudioService: 预加载失败 $e');
      _standbyPlayer.isReady = false;
      rethrow;
    }
  }

  /// 执行交叉淡入淡出切换
  Future<void> executeCrossfade(int durationMs) async {
    if (_isCrossfading) {
      debugPrint('DualAudioService: Crossfade已在进行中,跳过');
      return;
    }

    if (!_standbyPlayer.isReady) {
      debugPrint('DualAudioService: 待命播放器未就绪,无法执行crossfade');
      throw Exception('Standby player not ready');
    }

    _isCrossfading = true;
    _crossfadeState.value = CrossfadeState.fading;
    debugPrint('DualAudioService: 开始Crossfade,时长${durationMs}ms');

    final steps = 20; // 分20步完成渐变
    final stepDuration = Duration(milliseconds: durationMs ~/ steps);

    try {
      // Step 1: 启动待命播放器
      // 使用稍高的初始音量避免AudioTrack mute检测
      // 然后在Crossfade循环中立即降到0开始淡入
      await _standbyPlayer.player.setVolume(0.3); // 提高到0.3避免mute
      _standbyPlayer.volume = 0.3;
      await _standbyPlayer.player.seek(Duration.zero);

      // 我不知道just_audio和media_kit是怎么协调的
      // 这里不能使用异步 await , just_audio的实现会阻塞代码进行
      // 但是media_kit的实现不会阻塞代码进行, 神金
      // 你们两个库都给我飞起来
      _standbyPlayer.player.play();

      // Step 2: 交换播放器
      // 此时待命播放器接替播放，避免progress映射错误
      // UI 会自动切换到新active播放器的状态
      _swapPlayers();

      // 延长延迟确保AudioTrack完全启动
      await Future.delayed(const Duration(milliseconds: 150));

      // 添加超时保护，防止Crossfade卡住
      final maxDuration = Duration(milliseconds: durationMs + 2000); // 额外2秒容错
      Timer? timeoutTimer;
      timeoutTimer = Timer(maxDuration, () {
        if (_isCrossfading) {
          debugPrint('DualAudioService: Crossfade超时，强制完成');
          _isCrossfading = false; // 这会中断for循环
        }
      });

      // Step 3: 同时调整两个播放器的音量
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

        // 等待下一步
        await Future.delayed(stepDuration);

        // 检查是否被中断
        if (!_isCrossfading) {
          debugPrint('DualAudioService: Crossfade被中断');
          break;
        }
      }

      // 清理超时定时器
      timeoutTimer.cancel();

      // 如果被中断，执行清理
      if (!_isCrossfading &&
          _crossfadeState.value != CrossfadeState.completed) {
        debugPrint('DualAudioService: 清理中断的Crossfade状态');

        // 直接设置active播放器音量为1.0
        await _activePlayer.player.setVolume(1.0);
        _activePlayer.volume = 1.0;

        // 停止并重置standby播放器
        await _standbyPlayer.player.stop();
        await _standbyPlayer.player.seek(Duration.zero);
        _standbyPlayer.reset();

        _state.value = AudioState.playing;
        onStateChanged?.call(AudioState.playing);
        _crossfadeState.value = CrossfadeState.idle;

        return; // 提前返回，不执行后续的角色交换
      }

      // Step 4: 现在_activePlayer是原来的standby播放器，设置音量为1.0
      await _activePlayer.player.setVolume(1.0);
      _activePlayer.volume = 1.0;

      // Step 5: 确保新active播放器正在播放
      if (!_activePlayer.player.playing) {
        debugPrint('DualAudioService: 新active播放器未播放，重新启动');
        await _activePlayer.player.play();
      }

      // Step 6: 现在停止原active播放器(现在是standby)
      // 延迟一点确保新播放器已经开始播放
      await Future.delayed(const Duration(milliseconds: 100));
      await _standbyPlayer.player.stop();
      await _standbyPlayer.player.seek(Duration.zero);
      _standbyPlayer.reset();

      // Step 7: 强制更新状态为playing，确保UI正确显示
      _state.value = AudioState.playing;
      onStateChanged?.call(AudioState.playing); // 因为提前切换了播放器，UI 会自动更新，理论上不需要广播

      _crossfadeState.value = CrossfadeState.completed;
      debugPrint('DualAudioService: Crossfade完成,角色已交换');

      // 延迟重置状态
      Future.delayed(const Duration(seconds: 1), () {
        if (_crossfadeState.value == CrossfadeState.completed) {
          _crossfadeState.value = CrossfadeState.idle;
        }
      });
    } catch (e) {
      debugPrint('DualAudioService: Crossfade失败 $e');
      await _recoverFromCrossfadeError();
      rethrow;
    } finally {
      _isCrossfading = false;
    }
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
    debugPrint('DualAudioService: 播放器角色已交换');
  }

  /// 从Crossfade错误中恢复
  Future<void> _recoverFromCrossfadeError() async {
    debugPrint('DualAudioService: 从Crossfade错误中恢复');

    // 确保至少有一个播放器在播放
    if (!_activePlayer.player.playing && _standbyPlayer.player.playing) {
      _swapPlayers();
      await _activePlayer.player.setVolume(1.0);
      await _standbyPlayer.player.stop();
    } else if (!_standbyPlayer.player.playing) {
      await stop();
    }

    _crossfadeState.value = CrossfadeState.idle;
    _isCrossfading = false;
  }

  /// 取消crossfade并准备播放新歌曲
  /// 如果url为null，则只取消crossfade状态，不播放新歌曲
  Future<void> cancelAndPlay(String? url) async {
    _isCrossfading = false;
    _isPreloading = false;
    _crossfadeState.value = CrossfadeState.idle;

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
    if (_isCrossfading) {
      _isCrossfading = false;
      // 注意：不需要在这里暂停两个播放器
      // executeCrossfade的中断清理逻辑会处理
      debugPrint('DualAudioService: Crossfade中暂停');
    } else {
      await _activePlayer.player.pause();
    }
    _state.value = AudioState.paused;
    onStateChanged?.call(AudioState.paused);
  }

  /// 恢复播放
  Future<void> resume() async {
    // 直接恢复当前active播放器
    await _activePlayer.player.play();

    // 确保音量为1.0
    await _activePlayer.player.setVolume(1.0);
    _activePlayer.volume = 1.0;

    _state.value = AudioState.playing;
    onStateChanged?.call(AudioState.playing);
  }

  /// 停止播放
  Future<void> stop() async {
    await _activePlayer.player.stop();
    await _standbyPlayer.player.stop();
    await _standbyPlayer.player.seek(Duration.zero);
    _activePlayer.reset();
    _standbyPlayer.reset();
    _state.value = AudioState.stopped;
    _crossfadeState.value = CrossfadeState.idle;
    _isPreloading = false;
    _isCrossfading = false;
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
    debugPrint('DualAudioService: 播放模式切换为 ${_playMode.value}');
  }

  /// 释放资源
  Future<void> dispose() async {
    debugPrint('DualAudioService: 开始释放资源');

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

    // 清理状态
    _isPreloading = false;
    _isCrossfading = false;
    _crossfadeState.value = CrossfadeState.idle;

    debugPrint('DualAudioService: 资源释放完成');
  }
}
