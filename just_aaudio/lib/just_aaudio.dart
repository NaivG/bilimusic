import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_aaudio/models/adapter.dart';
import 'package:just_aaudio/players/aaudio.dart';
import 'package:just_aaudio/players/audio.dart';

/// just_aaudio插件
class JustAaudio {
  static const MethodChannel _channel = MethodChannel('just_aaudio');

  /// 获取平台版本
  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// 创建播放器
  static Future<void> createPlayer(String playerId) async {
    await _channel.invokeMethod('createPlayer', {'playerId': playerId});
  }

  /// 释放播放器
  static Future<void> disposePlayer(String playerId) async {
    await _channel.invokeMethod('disposePlayer', {'playerId': playerId});
  }
}

/// 音频播放器类，支持在just_audio和AAudio之间切换
class AudioPlayer {
  final String _playerId;
  late final just_audio.AudioPlayer _justAudioPlayer;
  late final AAudioPlayer _aaudioPlayer;
  late final JustAudioAdapter _justAudioAdapter;
  late final AudioPlayerAdapter _aaudioAdapter;
  late AudioPlayerAdapter _adapter;
  PlayerType _currentPlayerType = PlayerType.justAudio;

  // 跟踪最后一个文件路径
  String? _lastFilePath;
  bool _sourceFromFilePath = false;

  AudioPlayer({String? playerId})
      : _playerId = playerId ?? DateTime.now().microsecondsSinceEpoch.toString() {
    _justAudioPlayer = just_audio.AudioPlayer();
    _aaudioPlayer = AAudioPlayer(_playerId);
    _justAudioAdapter = JustAudioAdapter(_justAudioPlayer);
    _aaudioAdapter = _aaudioPlayer;
    _adapter = _justAudioAdapter;
  }

  /// 设置播放器类型
  Future<void> setPlayerType(PlayerType type) async {
    if (_currentPlayerType == type) return;

    // 保存当前状态
    final currentPosition = position;
    final isPlaying = playing;

    // 确定适用于新适配器的 source
    // 如果从 justAudio 切换且 source 来自 setFilePath，使用存储的 filePath 创建干净的 AudioSource.uri
    just_audio.AudioSource? sourceForNewAdapter;
    if (_currentPlayerType == PlayerType.justAudio && _sourceFromFilePath && _lastFilePath != null) {
      sourceForNewAdapter = just_audio.AudioSource.uri(Uri.file(_lastFilePath!));
    } else {
      sourceForNewAdapter = _justAudioPlayer.audioSource;
    }

    // 暂存器模式，带回滚
    final oldAdapter = _adapter;
    final oldPlayerType = _currentPlayerType;

    // 停止当前播放器
    await oldAdapter.stop();

    // 在临时变量中准备新适配器（暂不切换）
    AudioPlayerAdapter? preparedAdapter = (type == PlayerType.aaudio) ? _aaudioAdapter : _justAudioAdapter;

    // 尝试在新适配器上恢复状态
    try {
      if (sourceForNewAdapter != null) {
        await preparedAdapter!.setAudioSource(sourceForNewAdapter);

        if (currentPosition != Duration.zero) {
          await preparedAdapter!.seek(currentPosition);
        }

        if (isPlaying) {
          await preparedAdapter!.play();
        }
      }
    } catch (e) {
      debugPrint('[just_aaudio] Failed to restore state when switching to $type: $e');
      // 失败时回滚
      _adapter = oldAdapter;
      _currentPlayerType = oldPlayerType;

      // 尝试恢复旧适配器状态
      if (sourceForNewAdapter != null) {
        try {
          await oldAdapter.setAudioSource(sourceForNewAdapter);
          if (currentPosition != Duration.zero) {
            await oldAdapter.seek(currentPosition);
          }
          if (isPlaying) {
            await oldAdapter.play();
          }
        } catch (_) {
          // 回滚也失败时，重新抛出原始错误
        }
      }
      rethrow;
    }

    // 仅在新适配器准备成功后原子性提交切换
    _currentPlayerType = type;
    _adapter = preparedAdapter!;
  }

  /// 播放音频
  Future<void> play() => _adapter.play();

  /// 暂停音频
  Future<void> pause() => _adapter.pause();

  /// 停止音频
  Future<void> stop() => _adapter.stop();

  /// 跳转到指定位置
  Future<void> seek(Duration position) => _adapter.seek(position);

  /// 获取当前位置
  Duration get position => _adapter.position;

  /// 获取播放状态
  bool get playing => _adapter.playing;

  /// 获取播放时长
  Duration? get duration => _adapter.duration;

  /// 释放资源
  Future<void> dispose() => _adapter.dispose();

  /// 获取just_audio播放器实例
  just_audio.AudioPlayer get justAudioPlayer => _justAudioPlayer;

  /// 获取AAudio播放器实例
  AAudioPlayer get aaudioPlayer => _aaudioPlayer;

  /// 获取当前播放器类型
  PlayerType get currentPlayerType => _currentPlayerType;

  /// 获取播放事件流
  Stream<just_audio.PlayerEvent> get playerEventStream => _adapter.playerEventStream;

  /// 获取播放状态流
  Stream<just_audio.PlayerState> get playerStateStream => _adapter.playerStateStream;

  /// 获取当前位置流
  Stream<Duration> get positionStream => _adapter.positionStream;

  /// 获取播放速度
  double get speed => _adapter.speed;

  /// 设置播放速度
  Future<void> setSpeed(double speed) => _adapter.setSpeed(speed);

  /// 获取播放速度流
  Stream<double> get speedStream => _adapter.speedStream;

  /// 获取音量
  double get volume => _adapter.volume;

  /// 设置音量
  Future<void> setVolume(double volume) => _adapter.setVolume(volume);

  /// 获取音量流
  Stream<double> get volumeStream => _adapter.volumeStream;

  /// 获取播放状态
  just_audio.PlayerState get playerState => _adapter.playerState;

  /// 获取处理状态
  just_audio.ProcessingState get processingState => _adapter.processingState;

  /// 获取处理状态流
  Stream<just_audio.ProcessingState> get processingStateStream => _adapter.processingStateStream;

  /// 获取缓冲位置
  Duration get bufferedPosition => _adapter.bufferedPosition;

  /// 获取缓冲位置流
  Stream<Duration> get bufferedPositionStream => _adapter.bufferedPositionStream;

  /// 获取时长流
  Stream<Duration?> get durationStream => _adapter.durationStream;

  /// 获取播放流状态
  Stream<bool> get playingStream => _adapter.playingStream;

  /// 加载音频源
  Future<Duration?> setAudioSource(just_audio.AudioSource source, {Duration? initialPosition, bool preload = true}) {
    _sourceFromFilePath = false;  // 标记来源为直接调用
    return _adapter.setAudioSource(source, initialPosition: initialPosition, preload: preload);
  }

  /// Convenience method to set the audio source to a file, preloaded by
  /// default, with an initial position of zero by default.
  ///
  /// This is equivalent to:
  ///
  /// ```
  /// setAudioSource(AudioSource.uri(Uri.file(filePath), tag: tag),
  ///     initialPosition: Duration.zero, preload: true);
  /// ```
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) {
    _lastFilePath = filePath;
    _sourceFromFilePath = true;

    final source = just_audio.AudioSource.uri(Uri.file(filePath), tag: tag);
    return _adapter.setAudioSource(source, initialPosition: initialPosition ?? Duration.zero, preload: preload);
  }
}

enum PlayerType {
  // 使用just_audio原生播放器
  justAudio,
  // 使用AAudio播放器
  aaudio
}

