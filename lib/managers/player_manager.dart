import 'package:flutter/foundation.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/player_coordinator.dart';

// 播放模式枚举
enum PlayMode {
  sequential, // 顺序播放
  loop, // 单曲循环
  shuffle, // 随机播放
}

// 播放器状态枚举
enum AudioState {
  playing, // 正在播放
  paused, // 暂停
  stopped, // 停止
  buffering, // 缓冲中
}

/// 播放器管理器接口
/// 适配原有接口，内部使用协调器
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

  // 在播放列表中移动音乐位置（用于拖拽排序）
  Future<void> moveInPlaylist(int fromIndex, int toIndex);

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

  /// 获取crossfade倒计时（秒），-1表示未激活
  ValueListenable<int> get crossfadeCountdown;

  /// 注册crossfade倒计时变化监听器
  void addCountdownListener(Function(int) listener);

  /// 移除crossfade倒计时变化监听器
  void removeCountdownListener(Function(int) listener);
}

/// 播放器管理器实现
class StreamingPlayerManager extends PlayerManager {
  final PlayerCoordinator _coordinator;
  final List<Function(AudioState)> _stateListeners = [];
  final List<Function(Duration)> _positionListeners = [];
  final List<Function(PlayMode)> _playModeListeners = [];
  final List<Function(int)> _countdownListeners = [];

  StreamingPlayerManager(this._coordinator) {
    _setupListeners();
  }

  /// 设置监听器
  void _setupListeners() {
    _coordinator.state.addListener(_notifyStateListeners);
    _coordinator.position.addListener(_notifyPositionListeners);
    _coordinator.playMode.addListener(_notifyPlayModeListeners);
    _coordinator.crossfadeCountdown.addListener(_notifyCountdownListeners);
  }

  @override
  bool get isPlaying => _coordinator.isPlaying;

  @override
  AudioState get currentState => _coordinator.state.value;

  @override
  Music? get currentMusic => _coordinator.currentMusic;

  @override
  Duration get currentPosition => _coordinator.position.value;

  @override
  List<Music> get playList => _coordinator.playlist.value;

  @override
  List<Music> get playHistory => _coordinator.playHistory.value;

  @override
  List<Music> get favorites => _coordinator.favorites.value;

  @override
  PlayMode get playMode => _coordinator.playMode.value;

  @override
  Future<void> play(Music music) async {
    await _coordinator.playMusic(music);
  }

  @override
  Future<void> pause() async {
    await _coordinator.pause();
  }

  @override
  Future<void> resume() async {
    await _coordinator.resume();
  }

  @override
  Future<void> stop() async {
    await _coordinator.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _coordinator.seek(position);
  }

  @override
  Future<void> togglePlayMode() async {
    _coordinator.togglePlayMode();
  }

  @override
  Future<void> addToPlayList(Music music) async {
    await _coordinator.addToPlaylist(music);
  }

  @override
  Future<void> addAllToPlayList(List<Music> musics) async {
    await _coordinator.addAllToPlaylist(musics);
  }

  @override
  Future<void> playNextFromIndex(Music music) async {
    // 先添加到播放列表
    await _coordinator.addToPlaylist(music);

    // 获取当前索引
    final currentIndex = _coordinator.currentIndex;
    if (currentIndex != null) {
      // 找到新添加的音乐索引
      final playlist = _coordinator.playlist.value;
      final newIndex = playlist.indexWhere(
        (m) =>
            m.id == music.id &&
            (m.pages.isEmpty && music.pages.isEmpty ||
                m.pages.isNotEmpty &&
                    music.pages.isNotEmpty &&
                    m.pages[0].cid == music.pages[0].cid),
      );

      if (newIndex != -1) {
        // 将新音乐移动到当前播放的下一首
        final newPlaylist = List<Music>.from(playlist);
        final musicToMove = newPlaylist.removeAt(newIndex);
        final insertIndex = currentIndex + 1;
        newPlaylist.insert(insertIndex, musicToMove);

        // 更新播放列表（这里需要协调器提供更新方法）
        // 暂时使用现有方法
        await _coordinator.clearPlaylist();
        await _coordinator.addAllToPlaylist(newPlaylist);
        _coordinator.playAtIndex(insertIndex);
      }
    }
  }

  @override
  Future<void> clearPlayList() async {
    await _coordinator.clearPlaylist();
  }

  @override
  Future<void> removeFromPlayList(Music music) async {
    await _coordinator.removeFromPlaylist(music);
  }

  @override
  Future<void> moveInPlaylist(int fromIndex, int toIndex) async {
    await _coordinator.moveInPlaylist(fromIndex, toIndex);
  }

  @override
  void addStateListener(Function(AudioState) listener) {
    _stateListeners.add(listener);
  }

  @override
  void removeStateListener(Function(AudioState) listener) {
    _stateListeners.remove(listener);
  }

  @override
  void addPositionListener(Function(Duration) listener) {
    _positionListeners.add(listener);
  }

  @override
  void removePositionListener(Function(Duration) listener) {
    _positionListeners.remove(listener);
  }

  @override
  void addPlayModeListener(Function(PlayMode) listener) {
    _playModeListeners.add(listener);
  }

  @override
  void removePlayModeListener(Function(PlayMode) listener) {
    _playModeListeners.remove(listener);
  }

  @override
  Future<void> playNext() async {
    await _coordinator.playNext();
  }

  @override
  Future<void> playPrevious() async {
    await _coordinator.playPrevious();
  }

  @override
  Future<void> playAtIndex(int index) async {
    await _coordinator.playAtIndex(index);
  }

  @override
  int getPlaylistLength() {
    return _coordinator.playlistLength;
  }

  @override
  int getCurrentIndex() {
    return _coordinator.currentIndex ?? -1;
  }

  @override
  double getProgressPercentage() {
    return _coordinator.progressPercentage;
  }

  @override
  ValueListenable<int> get crossfadeCountdown =>
      _coordinator.crossfadeCountdown;

  @override
  void addCountdownListener(Function(int) listener) {
    _countdownListeners.add(listener);
  }

  @override
  void removeCountdownListener(Function(int) listener) {
    _countdownListeners.remove(listener);
  }

  @override
  Future<void> dispose() async {
    _coordinator.state.removeListener(_notifyStateListeners);
    _coordinator.position.removeListener(_notifyPositionListeners);
    _coordinator.playMode.removeListener(_notifyPlayModeListeners);
    _coordinator.crossfadeCountdown.removeListener(_notifyCountdownListeners);
    await _coordinator.dispose();
  }

  @override
  Future<void> addToFavorites(Music music) async {
    await _coordinator.addToFavorites(music);
  }

  @override
  Future<void> removeFromFavorites(Music music) async {
    await _coordinator.removeFromFavorites(music);
  }

  @override
  bool isFavorite(Music music) {
    return _coordinator.isFavorite(music);
  }

  /// 通知状态监听器
  void _notifyStateListeners() {
    final state = _coordinator.state.value;
    for (final listener in _stateListeners) {
      listener(state);
    }
  }

  /// 通知位置监听器
  void _notifyPositionListeners() {
    final position = _coordinator.position.value;
    for (final listener in _positionListeners) {
      listener(position);
    }
  }

  /// 通知播放模式监听器
  void _notifyPlayModeListeners() {
    final playMode = _coordinator.playMode.value;
    for (final listener in _playModeListeners) {
      listener(playMode);
    }
  }

  /// 通知倒计时监听器
  void _notifyCountdownListeners() {
    final countdown = _coordinator.crossfadeCountdown.value;
    for (final listener in _countdownListeners) {
      listener(countdown);
    }
  }
}
