import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/managers/player_manager.dart';

/// 音频处理器
/// 适配 audio_service 接口
class AudioHandlerConnector extends BaseAudioHandler {
  final PlayerManager playerManager;

  AudioHandlerConnector(this.playerManager);

  @override
  Future<void> play() async {
    // 如果当前有音乐在播放，就恢复播放；否则，如果播放列表不为空，就播放当前曲目
    if (playerManager.currentState == AudioState.paused) {
      await playerManager.resume();
    } else if (playerManager.playList.isNotEmpty) {
      // 尝试播放当前曲目
      final currentMusic = playerManager.currentMusic;
      if (currentMusic != null) {
        await playerManager.play(currentMusic);
      }
    }
  }

  @override
  Future<void> pause() async {
    await playerManager.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await playerManager.seek(position);
  }

  @override
  Future<void> stop() async {
    await playerManager.stop();
    playbackState.add(PlaybackState(
      controls: [],
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
    ));
  }

  @override
  Future<void> skipToNext() async {
    await playerManager.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await playerManager.playPrevious();
  }
  
  // 添加收藏功能
  @override
  Future<void> customAction(String action, [Map<String, dynamic>? extras]) async {
    switch (action) {
      case 'favorite':
        final currentMusic = playerManager.currentMusic;
        if (currentMusic != null) {
          if (playerManager.isFavorite(currentMusic)) {
            await playerManager.removeFromFavorites(currentMusic);
          } else {
            await playerManager.addToFavorites(currentMusic);
          }
        }
        break;
      default:
        super.customAction(action, extras);
        break;
    }
  }
}