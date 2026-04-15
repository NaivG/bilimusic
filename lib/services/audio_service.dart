import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:rxdart/rxdart.dart';

/// 音频播放核心服务
/// 职责：管理音频播放器的生命周期和播放控制
class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ValueNotifier<AudioState> _state = ValueNotifier(AudioState.stopped);
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<PlayMode> _playMode = ValueNotifier(PlayMode.sequential);

  late BaseAudioHandler _audioHandler;
  final List<StreamSubscription> _subscriptions = [];

  AudioService();

  /// 初始化音频服务
  void initialize(BaseAudioHandler audioHandler) {
    _audioHandler = audioHandler;
    _initAudioPlayer();
  }

  /// 配置音频播放器以减少管道溢出
  void _configureAudioPlayer() {
    // TODO: 配置音频播放器参数以减少管道溢出
  }

  /// 初始化音频播放器
  void _initAudioPlayer() {
    // 配置音频播放器以减少管道溢出
    _configureAudioPlayer();

    // 播放状态监听
    final playerStateSubscription = _audioPlayer.playerStateStream.listen(
      (playerState) {
        final isPlaying = playerState.playing;
        final processingState = playerState.processingState;

        if (processingState == ProcessingState.completed) {
          _state.value = AudioState.stopped;
          _handlePlaybackCompleted();
        } else {
          _state.value = isPlaying ? AudioState.playing : AudioState.paused;
        }
      },
      onError: (error) {
        debugPrint("Audio player state stream error: $error");
      },
    );

    // 播放位置监听（使用防抖减少更新频率）
    final positionSubscription = _audioPlayer.positionStream
        .transform(
          ThrottleStreamTransformer<Duration>(
            (_) => Stream<Duration>.periodic(
              const Duration(milliseconds: 200),
              (_) => Duration.zero,
            ),
          ),
        )
        .listen(
          (position) {
            _position.value = position;
            // 位置更新由player_coordinator统一处理PlaybackState
          },
          onError: (error) {
            debugPrint("Audio player position stream error: $error");
          },
        );

    // 音频时长监听
    final durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _duration.value = duration;
      }
    });

    _subscriptions.add(playerStateSubscription);
    _subscriptions.add(positionSubscription);
    _subscriptions.add(durationSubscription);

    // 初始化音频服务状态
    _audioHandler.playbackState.add(
      PlaybackState(
        controls: [],
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  /// 播放音频文件
  Future<void> playFile(String filePath) async {
    try {
      _state.value = AudioState.buffering;
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      _state.value = AudioState.playing;
    } catch (e) {
      _state.value = AudioState.stopped;
      debugPrint('Error playing audio file: $e');
      rethrow;
    }
  }

  /// 播放音频URL
  Future<void> playUrl(String url) async {
    try {
      _state.value = AudioState.buffering;
      await _audioPlayer.setUrl(url);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      _state.value = AudioState.playing;
    } catch (e) {
      _state.value = AudioState.stopped;
      debugPrint('Error playing audio URL: $e');
      rethrow;
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    await _audioPlayer.pause();
    _state.value = AudioState.paused;
  }

  /// 恢复播放
  Future<void> resume() async {
    await _audioPlayer.play();
    _state.value = AudioState.playing;
  }

  /// 停止播放
  Future<void> stop() async {
    await _audioPlayer.stop();
    _state.value = AudioState.stopped;
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final currentIndex = _playMode.value.index;
    final nextIndex = (currentIndex + 1) % PlayMode.values.length;
    _playMode.value = PlayMode.values[nextIndex];

    // 通知音频服务播放模式变化
    _audioHandler.customEvent.add({
      'type': 'playModeChanged',
      'mode': _playMode.value.index,
    });
  }

  /// 处理播放完成事件
  void _handlePlaybackCompleted() {
    // 根据播放模式处理
    switch (_playMode.value) {
      case PlayMode.loop:
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.play();
        break;
      case PlayMode.sequential:
      case PlayMode.shuffle:
        // 状态已设为 stopped，协调器会检测到并处理下一首
        break;
    }
  }

  /// 转换处理状态
  @Deprecated(
    'Use AudioProcessingState directly instead of converting from ProcessingState',
  )
  AudioProcessingState _convertProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.buffering;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 获取当前播放状态
  ValueListenable<AudioState> get state => _state;

  /// 获取当前播放位置
  ValueListenable<Duration> get position => _position;

  /// 获取当前音频时长
  ValueListenable<Duration> get duration => _duration;

  /// 获取当前播放模式
  ValueListenable<PlayMode> get playMode => _playMode;

  /// 获取是否正在播放
  bool get isPlaying => _state.value == AudioState.playing;

  /// 获取当前播放位置（同步）
  Duration get currentPosition => _audioPlayer.position;

  /// 获取当前音频时长（同步）
  Duration get currentDuration => _audioPlayer.duration ?? Duration.zero;

  /// 获取播放进度百分比
  double get progressPercentage {
    if (_audioPlayer.duration == null ||
        _audioPlayer.duration!.inMilliseconds == 0) {
      return 0.0;
    }
    return _audioPlayer.position.inMilliseconds /
        _audioPlayer.duration!.inMilliseconds;
  }

  /// 释放资源
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _audioPlayer.dispose();
  }
}
