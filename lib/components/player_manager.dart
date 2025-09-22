import 'package:bilimusic/models/music.dart';

// 播放模式枚举
enum PlayMode {
  sequential, // 顺序播放
  loop,     // 单曲循环
  shuffle   // 随机播放
}

// 播放器状态枚举
enum AudioState {
  playing,  // 正在播放
  paused,   // 暂停
  stopped,  // 停止
  buffering // 缓冲中
}

// 播放器管理器接口
abstract class PlayerManager {
  bool get isPlaying;

  // 获取当前播放状态
  AudioState get currentState;

  // 获取当前播放的音乐
  Music? get currentMusic;

  // 获取当前播放位置
  Duration get currentPosition;

  // 获取播放列表
  List<Music> get playList;

  // 获取播放历史记录
  List<Music> get playHistory;

  // 获取收藏列表
  List<Music> get favorites;

  // 获取当前播放模式
  PlayMode get playMode;

  // 播放指定音乐
  Future<void> play(Music music);

  // 暂停播放
  Future<void> pause();

  // 继续播放
  Future<void> resume();

  // 停止播放
  Future<void> stop();

  // 跳转到指定位置
  Future<void> seek(Duration position);

  // 切换播放模式
  Future<void> togglePlayMode();

  // 添加单个音乐到播放列表
  Future<void> addToPlayList(Music music);

  // 添加多个音乐到播放列表
  Future<void> addAllToPlayList(List<Music> musics);

  // 添加单个音乐到播放列表
  Future<void> playNextFromIndex(Music music);

  // 清空播放列表
  Future<void> clearPlayList();

  // 从播放列表中移除指定音乐
  Future<void> removeFromPlayList(Music music);

  // 注册播放状态变化监听器
  void addStateListener(Function(AudioState) listener);

  // 移除播放状态变化监听器
  void removeStateListener(Function(AudioState) listener);

  // 注册播放位置变化监听器
  void addPositionListener(Function(Duration) listener);

  // 移除播放位置变化监听器
  void removePositionListener(Function(Duration) listener);

  /// 注册播放模式变化监听器
  void addPlayModeListener(Function(PlayMode) listener);

  /// 移除播放模式变化监听器
  void removePlayModeListener(Function(PlayMode) listener);

  // 播放下一首
  Future<void> playNext();

  // 播放上一首
  Future<void> playPrevious();

  // 播放指定索引处的音乐
  Future<void> playAtIndex(int index);

  // 获取播放列表长度
  int getPlaylistLength();

  // 获取当前播放索引
  int getCurrentIndex();

  // 获取当前播放进度（百分比）
  double getProgressPercentage();

  // 销毁播放器
  Future<void> dispose();
  
  // 收藏相关方法
  Future<void> addToFavorites(Music music);
  Future<void> removeFromFavorites(Music music);
  bool isFavorite(Music music);
}