import 'dart:async';
import 'package:just_audio/just_audio.dart' as just_audio;

/// 音频播放器适配器接口
/// 统一 just_audio 和 AAudio 的 API
abstract class AudioPlayerAdapter {
  // Actions
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<Duration?> setAudioSource(just_audio.AudioSource source, {Duration? initialPosition, bool preload = true});
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);

  // Getters
  bool get playing;
  Duration get position;
  Duration? get duration;
  double get speed;
  double get volume;
  just_audio.PlayerState get playerState;
  just_audio.ProcessingState get processingState;
  Duration get bufferedPosition;

  // Streams
  Stream<just_audio.PlayerEvent> get playerEventStream;
  Stream<just_audio.PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<double> get speedStream;
  Stream<double> get volumeStream;
  Stream<just_audio.ProcessingState> get processingStateStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;

  Future<void> dispose();
}