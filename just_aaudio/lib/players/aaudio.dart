import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_aaudio/models/adapter.dart';
import '../just_aaudio.dart' show JustAaudio;

/// AAudio播放器封装
class AAudioPlayer implements AudioPlayerAdapter {
  static const String _methodChannelPrefix = 'github.naivg.just_aaudio.methods.';
  static const String _eventChannelPrefix = 'github.naivg.just_aaudio.events.';
  final String _playerId;
  final MethodChannel _channel;
  final EventChannel _positionEventChannel;
  StreamSubscription? _positionSubscription;
  Timer? _completionTimer;
  
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1.0;
  double _volume = 1.0;
  just_audio.ProcessingState _processingState = just_audio.ProcessingState.idle;
  Duration _bufferedPosition = Duration.zero;

  // 原生 EventChannel 推送位置更新

  final StreamController<just_audio.PlayerEvent> _playerEventController =
      StreamController<just_audio.PlayerEvent>.broadcast();
  @override
  late Stream<just_audio.PlayerEvent> playerEventStream;

  // 新增控制器
  final StreamController<just_audio.PlayerState> _playerStateController =
      StreamController<just_audio.PlayerState>.broadcast();
  @override
  late Stream<just_audio.PlayerState> playerStateStream;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  @override
  late Stream<Duration> positionStream;

  final StreamController<double> _speedController =
      StreamController<double>.broadcast();
  @override
  late Stream<double> speedStream;

  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  @override
  late Stream<double> volumeStream;

  final StreamController<just_audio.ProcessingState> _processingStateController =
      StreamController<just_audio.ProcessingState>.broadcast();
  @override
  late Stream<just_audio.ProcessingState> processingStateStream;

  final StreamController<Duration> _bufferedPositionController =
      StreamController<Duration>.broadcast();
  @override
  late Stream<Duration> bufferedPositionStream;

  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  @override
  late Stream<Duration?> durationStream;

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  @override
  late Stream<bool> playingStream;

  AAudioPlayer(String playerId)
      : _playerId = playerId,
        _channel = MethodChannel(_methodChannelPrefix + playerId),
        _positionEventChannel = EventChannel(_eventChannelPrefix + playerId) {
    // 确保原生端创建了播放器实例
    JustAaudio.createPlayer(playerId).catchError((e) {
      debugPrint("[just_aaudio] Failed to create native player: $e");
    });

    playerEventStream = _playerEventController.stream;
    playerStateStream = _playerStateController.stream;
    positionStream = _positionController.stream;
    speedStream = _speedController.stream;
    volumeStream = _volumeController.stream;
    processingStateStream = _processingStateController.stream;
    bufferedPositionStream = _bufferedPositionController.stream;
    durationStream = _durationController.stream;
    playingStream = _playingController.stream;

  }

  // 初始化位置监听（EventChannel 方式，原生端推送）
  void _ensurePositionListener() {
    _positionSubscription?.cancel();
    _positionSubscription = _positionEventChannel
        .receiveBroadcastStream()
        .listen((dynamic event) {
          if (event != null && event is int) {
            final newPosition = Duration(milliseconds: event);
            _position = newPosition;
            _positionController.add(_position);

            // 检查播放是否完成
            if (_isPlaying && _duration != null && _duration! > Duration.zero) {
              if (newPosition >= _duration!) {
                _isPlaying = false;
                _processingState = just_audio.ProcessingState.completed;
                _playingController.add(false);
                _updatePlayerState();
                _stopCompletionTimer();
              }
            }
          }
        }, onError: (dynamic error) {
          // 忽略错误，原生端可能尚未准备好
        });
  }

  /// 启动完成检测定时器（后备机制）
  void _startCompletionTimer() {
    _stopCompletionTimer();
    _completionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isPlaying && _duration != null && _duration! > Duration.zero) {
        if (_position >= _duration!) {
          _isPlaying = false;
          _processingState = just_audio.ProcessingState.completed;
          _playingController.add(false);
          _updatePlayerState();
          _stopCompletionTimer();
        }
      } else if (!_isPlaying) {
        _stopCompletionTimer();
      }
    });
  }

  /// 停止完成检测定时器
  void _stopCompletionTimer() {
    _completionTimer?.cancel();
    _completionTimer = null;
  }

  /// 加载音频源
  @override
  Future<Duration?> setAudioSource(just_audio.AudioSource source, {Duration? initialPosition, bool preload = true}) async {
    // 处理不同类型的音频源
    if (source is just_audio.UriAudioSource) {
      try {
        String filePath = source.uri.toFilePath();
        
        // 使用Android原生API进行音频转换
        String fileUri = 'file://$filePath';
        await _channel.invokeMethod('load', {'uri': fileUri});
      } catch (e) {
        // 检查是否是格式不支持的错误
        if (e is PlatformException && e.code == 'LoadError') {
          // 提供更明确的错误信息
          throw PlatformException(
            code: 'LoadError',
            message: 'Failed to load audio file. AAudio player supports WAV, AIFF and other formats supported by libsndfile. '
                     'For other formats, Android native conversion is attempted but may have failed. '
                     'Please use just_audio player type for direct format support.',
            details: e.details,
          );
        }
        rethrow;
      }
    } else if (source is just_audio.ProgressiveAudioSource) {
      try {
        String filePath = source.uri.toFilePath();
        
        // 使用Android原生API进行音频转换
        String fileUri = 'file://$filePath';
        await _channel.invokeMethod('load', {'uri': fileUri});
      } catch (e) {
        // 检查是否是格式不支持的错误
        if (e is PlatformException && e.code == 'LoadError') {
          // 提供更明确的错误信息
          throw PlatformException(
            code: 'LoadError',
            message: 'Failed to load audio file. AAudio player supports WAV, AIFF and other formats supported by libsndfile. '
                     'For other formats, Android native conversion is attempted but may have failed. '
                     'Please use just_audio player type for direct format support.',
            details: e.details,
          );
        }
        rethrow;
      }
    } else {
      // 对于其他类型的音频源，可能需要特殊处理
      throw UnsupportedError('AudioSource type not supported by AAudio player: ${source.runtimeType}');
    }
    
    // 从原生端获取时长
    final durationMs = await _channel.invokeMethod('getDuration');
    if (durationMs != null && durationMs > 0) {
      _duration = Duration(milliseconds: durationMs);
      _durationController.add(_duration);
    }
    
    return _duration;
  }


  /// 播放音频
  @override
  Future<void> play() async {
    await _channel.invokeMethod('play');
    _isPlaying = true;
    _processingState = just_audio.ProcessingState.ready;
    _playingController.add(_isPlaying);
    _updatePlayerState();
    // 确保位置监听器激活
    _ensurePositionListener();
    _startCompletionTimer();
  }

  /// 暂停音频
  @override
  Future<void> pause() async {
    await _channel.invokeMethod('pause');
    _isPlaying = false;
    _processingState = just_audio.ProcessingState.ready;
    _playingController.add(_isPlaying);
    _updatePlayerState();
    _stopCompletionTimer();
  }

  /// 停止音频
  @override
  Future<void> stop() async {
    await _channel.invokeMethod('stop');
    _isPlaying = false;
    _position = Duration.zero;
    _processingState = just_audio.ProcessingState.idle;
    _playingController.add(_isPlaying);
    _positionController.add(_position);
    _updatePlayerState();
    _stopCompletionTimer();
  }

  /// 跳转到指定位置
  @override
  Future<void> seek(Duration position) async {
    await _channel.invokeMethod('seekTo', {
      'position': position.inMilliseconds,
    });
    _position = position;
    _positionController.add(_position);
  }

  /// 获取播放状态
  @override
  bool get playing => _isPlaying;

  /// 获取当前位置
  @override
  Duration get position => _position;

  /// 获取播放时长
  @override
  Duration? get duration => _duration;

  /// 获取播放速度
  @override
  double get speed => _speed;

  /// 设置播放速度
  @override
  Future<void> setSpeed(double speed) async {
    await _channel.invokeMethod('setSpeed', {
      'speed': speed,
    });
    _speed = speed;
    _speedController.add(_speed);
  }

  /// 获取音量
  @override
  double get volume => _volume;

  /// 设置音量
  @override
  Future<void> setVolume(double volume) async {
    await _channel.invokeMethod('setVolume', {
      'volume': volume,
    });
    _volume = volume;
    _volumeController.add(_volume);
  }

  /// 获取播放状态
  @override
  just_audio.PlayerState get playerState => just_audio.PlayerState(_isPlaying, _processingState);

  /// 获取处理状态
  @override
  just_audio.ProcessingState get processingState => _processingState;

  /// 获取缓冲位置
  @override
  Duration get bufferedPosition => _bufferedPosition;

  /// 释放资源
  @override
  Future<void> dispose() async {
    // 取消位置监听订阅
    _stopCompletionTimer();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    await JustAaudio.disposePlayer(_playerId);
    _playerEventController.close();
    _playerStateController.close();
    _positionController.close();
    _speedController.close();
    _volumeController.close();
    _processingStateController.close();
    _bufferedPositionController.close();
    _durationController.close();
    _playingController.close();
  }

  void _updatePlayerState() {
    _playerStateController.add(just_audio.PlayerState(_isPlaying, _processingState));
    _processingStateController.add(_processingState);
  }
}