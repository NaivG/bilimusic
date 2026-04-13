import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/models/music.dart';

/// 通知管理服务
/// 职责：管理音频通知的更新和显示
class NotificationService {
  BaseAudioHandler? _audioHandler;

  NotificationService();

  /// 初始化通知服务
  void initialize(BaseAudioHandler audioHandler) {
    _audioHandler = audioHandler;
  }

  /// 更新媒体通知信息
  /// 注意：直接调用，不依赖UI线程回调，确保后台也能正常工作
  void updateMediaInfo(Music music) {
    final mediaItem = MediaItem(
      id: music.id,
      title: music.title,
      artist: music.artist,
      album: music.album,
      duration: music.duration ?? Duration.zero,
      artUri: Uri.parse(music.coverUrl),
    );

    _audioHandler?.mediaItem.add(mediaItem);
  }

  /// 更新播放状态
  void updatePlaybackState({
    required bool playing,
    required Duration position,
    Duration? bufferedPosition,
    double speed = 1.0,
    AudioProcessingState processingState = AudioProcessingState.ready,
    List<MediaControl> controls = const [],
  }) {
    _audioHandler?.playbackState.add(
      PlaybackState(
        controls: controls,
        playing: playing,
        updatePosition: position,
        bufferedPosition: bufferedPosition ?? Duration.zero,
        speed: speed,
        processingState: processingState,
      ),
    );
  }

  /// 获取媒体控制按钮
  List<MediaControl> getMediaControls({
    required bool hasPlaylist,
    required int? currentIndex,
    required int playlistLength,
    required bool isPlaying,
    required bool isFavorite,
  }) {
    // 当播放列表为空时返回空列表
    if (!hasPlaylist) {
      return [];
    }

    // 当播放列表不为空但当前索引无效时返回基本控件
    if (currentIndex == null || currentIndex < 0) {
      return [MediaControl.play];
    }

    return [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl(
        androidIcon: 'drawable/ic_favorite',
        label: isFavorite ? '取消收藏' : '收藏',
        action: MediaAction.custom,
        customAction: const CustomMediaAction(name: 'favorite'),
      ),
    ];
  }

  /// 发送自定义事件
  void sendCustomEvent(Map<String, dynamic> event) {
    _audioHandler?.customEvent.add(event);
  }

  /// 停止通知
  void stop() {
    _audioHandler?.playbackState.add(
      PlaybackState(
        controls: [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
      ),
    );
  }
}
