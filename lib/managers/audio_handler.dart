import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/services/player_coordinator.dart';

/// 音频处理器
/// 适配 audio_service 接口
class AudioHandlerConnector extends BaseAudioHandler {
  final PlayerCoordinator playerCoordinator;

  AudioHandlerConnector(this.playerCoordinator);

  @override
  Future<void> play() async {
    if (playerCoordinator.playerState.value is PlayerPaused) {
      await playerCoordinator.resume();
    } else if (playerCoordinator.playlistLength > 0) {
      final currentMusic = playerCoordinator.currentMusic;
      if (currentMusic != null) {
        await playerCoordinator.playMusic(currentMusic);
      }
    }
  }

  @override
  Future<void> pause() async {
    await playerCoordinator.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await playerCoordinator.seek(position);
  }

  @override
  Future<void> stop() async {
    await playerCoordinator.stop();
    playbackState.add(
      PlaybackState(
        controls: [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    await playerCoordinator.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await playerCoordinator.playPrevious();
  }

  @override
  Future<void> customAction(
    String action, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (action) {
      case 'favorite':
        final currentMusic = playerCoordinator.currentMusic;
        if (currentMusic != null) {
          if (playerCoordinator.isFavorite(currentMusic)) {
            await playerCoordinator.removeFromFavorites(currentMusic);
          } else {
            await playerCoordinator.addToFavorites(currentMusic);
          }
        }
        break;
      default:
        super.customAction(action, extras);
        break;
    }
  }
}
