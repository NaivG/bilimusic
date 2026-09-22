import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/domain/music.dart';

/// 通知管理服务
/// 职责：管理音频通知的更新和显示
///
/// 它同时是**我们上报给系统媒体会话的唯一出口**：`playbackState` / `mediaItem`
/// 进到这里，audio_service 再转给 Android 的 MediaSession。系统对媒体键
/// （耳机键）的方向判定用的就是这个状态，所以这里留了一份"最后上报值"给
/// 诊断测试页读。
class NotificationService {
  BaseAudioHandler? _audioHandler;

  /// 最后一次上报给系统的媒体会话状态（null = 还没上报过）。
  PlaybackState? _lastPlaybackState;

  /// 最后一次上报的曲目。
  MediaItem? _lastMediaItem;

  /// 上报次数（含只改进度的那些，用于判断会话是否还在被喂）。
  int _playbackStatePushCount = 0;

  PlaybackState? get lastPlaybackState => _lastPlaybackState;
  MediaItem? get lastMediaItem => _lastMediaItem;
  int get playbackStatePushCount => _playbackStatePushCount;

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

    _lastMediaItem = mediaItem;
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
    final state = PlaybackState(
      controls: controls,
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition ?? Duration.zero,
      speed: speed,
      processingState: processingState,
    );

    _lastPlaybackState = state;
    _playbackStatePushCount++;
    _audioHandler?.playbackState.add(state);
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
        androidIcon: isFavorite
            ? 'drawable/ic_favorite'
            : 'drawable/ic_favorite_border',
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
    final state = PlaybackState(
      controls: [],
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
    );
    _lastPlaybackState = state;
    _playbackStatePushCount++;
    _audioHandler?.playbackState.add(state);
  }
}
