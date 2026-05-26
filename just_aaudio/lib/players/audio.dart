import 'dart:async';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_aaudio/models/adapter.dart';

/// just_audio 适配器
class JustAudioAdapter implements AudioPlayerAdapter {
  final just_audio.AudioPlayer _player;

  JustAudioAdapter(this._player);

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  double get speed => _player.speed;

  @override
  double get volume => _player.volume;

  @override
  just_audio.PlayerState get playerState => _player.playerState;

  @override
  just_audio.ProcessingState get processingState => _player.processingState;

  @override
  Duration get bufferedPosition => _player.bufferedPosition;

  @override
  Stream<just_audio.PlayerEvent> get playerEventStream => _player.playerEventStream;

  @override
  Stream<just_audio.PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<double> get speedStream => _player.speedStream;

  @override
  Stream<double> get volumeStream => _player.volumeStream;

  @override
  Stream<just_audio.ProcessingState> get processingStateStream => _player.processingStateStream;

  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<Duration?> setAudioSource(just_audio.AudioSource source, {Duration? initialPosition, bool preload = true}) {
    return _player.setAudioSource(source, initialPosition: initialPosition, preload: preload);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
