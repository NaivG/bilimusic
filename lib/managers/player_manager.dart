import 'package:flutter/foundation.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/services/player_coordinator.dart';

// 播放模式枚举
enum PlayMode {
  sequential, // 顺序播放
  loop, // 单曲循环
  shuffle, // 随机播放
}

// 播放器状态枚举（仅作 AudioHandler/旧 UI 兼容标签；广播通道已切到 PlayerState）
enum AudioState {
  playing, // 正在播放
  paused, // 暂停
  stopped, // 停止
  buffering, // 缓冲中
}

/// 播放器管理器接口
/// UI 监听请直接用 ValueListenableBuilder（playerManager.playerState/position/playModeValue），
/// 不要再用旧的 addXxxListener —— 那些接口已删除。
abstract class PlayerManager {
  PlayerManager._internal(this._coordinator);

  final PlayerCoordinator _coordinator;

  bool get isPlaying;

  // 获取当前播放状态（兼容旧 AudioHandler，从 PlayerState 派生）
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

  // ============ 监听通道（ValueListenable，UI 用 ValueListenableBuilder 包裹） ============

  /// 播放器高层状态（sealed class：idle/buffering/playing/paused/completed）
  /// PlayerPlaying 自带 fadeCountdown，可识别当前是否在 crossfade 中。
  ValueListenable<PlayerState> get playerState;

  /// 旧 AudioState 派生桥接（仅给极少数还没迁移的 UI 用；新代码用 playerState）
  ValueListenable<AudioState> get state;

  /// 播放位置
  ValueListenable<Duration> get position;

  /// 总时长
  ValueListenable<Duration> get duration;

  /// 播放模式
  ValueListenable<PlayMode> get playModeValue;

  /// 当前播放索引（ValueListenable，用于 DetailPage 等监听切歌）
  ValueListenable<int?> get currentIndexNotifier;
}

/// 播放器管理器实现（单例，纯 facade —— 只代理 Coordinator，不维护副本状态）
class StreamingPlayerManager extends PlayerManager {
  static StreamingPlayerManager? _instance;
  static StreamingPlayerManager get instance {
    if (_instance == null) {
      throw Exception(
        'StreamingPlayerManager has not been initialized. Call StreamingPlayerManager.initialize(coordinator) first.',
      );
    }
    return _instance!;
  }

  /// 初始化单例
  factory StreamingPlayerManager.initialize(PlayerCoordinator coordinator) {
    _instance ??= StreamingPlayerManager._internal(coordinator);
    return _instance!;
  }

  StreamingPlayerManager._internal(super.coordinator) : super._internal() {
    // 把 PlayerState 同步到旧 AudioState ValueNotifier，保持向后兼容
    _coordinator.playerState.addListener(_syncLegacyState);
  }

  @override
  bool get isPlaying => _coordinator.isPlaying;

  @override
  AudioState get currentState => _audioStateOf(_coordinator.playerState.value);

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
  ValueListenable<PlayerState> get playerState => _coordinator.playerState;

  @override
  late final ValueNotifier<AudioState> state =
      ValueNotifier(currentState);

  @override
  ValueListenable<Duration> get position => _coordinator.position;

  @override
  ValueListenable<Duration> get duration => _coordinator.duration;

  @override
  ValueListenable<PlayMode> get playModeValue => _coordinator.playMode;

  @override
  ValueListenable<int?> get currentIndexNotifier =>
      _coordinator.currentIndexNotifier;

  void _syncLegacyState() {
    final s = _audioStateOf(_coordinator.playerState.value);
    if (state.value != s) {
      state.value = s;
    }
  }

  static AudioState _audioStateOf(PlayerState s) {
    return switch (s) {
      PlayerIdle _ => AudioState.stopped,
      PlayerBuffering _ => AudioState.buffering,
      PlayerPlaying _ => AudioState.playing,
      PlayerPaused _ => AudioState.paused,
      PlayerCompleted _ => AudioState.stopped,
    };
  }

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
    await _coordinator.addToPlaylist(music);

    final currentIndex = _coordinator.currentIndex;
    if (currentIndex != null) {
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
        final newPlaylist = List<Music>.from(playlist);
        final musicToMove = newPlaylist.removeAt(newIndex);
        final insertIndex = currentIndex + 1;
        newPlaylist.insert(insertIndex, musicToMove);

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
  Future<void> dispose() async {
    _coordinator.playerState.removeListener(_syncLegacyState);
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
}