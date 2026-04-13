import 'dart:async';
import 'dart:math';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/services/notification_service.dart';
import 'package:bilimusic/services/api_service.dart';
import 'package:bilimusic/managers/settings_manager.dart';

/// 播放器协调器
/// 职责: 协调各个服务的工作,提供统一的播放器接口,管理双播放器的切换和预加载
class PlayerCoordinator {
  final DualAudioService _audioService;
  final SettingsManager _settingsManager;
  final PlaylistService _playlistService;
  final NotificationService _notificationService;
  final ApiService _apiService;

  final Random _random = Random();
  bool _isHandlingCompletion = false;
  Timer? _debounceTimer;
  Timer? _countdownTimer; // 倒计时定时器
  DateTime? _crossfadeStartTime; // crossfade开始时间戳
  bool _isCountdownActive = false; // 防止重复触发
  final ValueNotifier<int> _crossfadeCountdown = ValueNotifier(
    -1,
  ); // 倒计时值（秒），-1表示未激活
  Music? _preloadedMusic; // 记录已预加载的音乐

  PlayerCoordinator({
    required DualAudioService audioService,
    required SettingsManager settingsManager,
    required PlaylistService playlistService,
    required NotificationService notificationService,
    required ApiService apiService,
  }) : _audioService = audioService,
       _settingsManager = settingsManager,
       _playlistService = playlistService,
       _notificationService = notificationService,
       _apiService = apiService {
    _setupEventHandlers();
  }

  /// 设置事件处理器
  void _setupEventHandlers() {
    // 设置DualAudioService的回调
    _audioService.onPlaybackCompleted = _handlePlaybackCompleted;
    _audioService.onPositionChanged = _onPositionChanged;
    _audioService.onStateChanged = _onAudioStateChanged;

    // 监听播放模式变化
    _audioService.playMode.addListener(_onPlayModeChanged);

    // 监听播放列表变化
    _playlistService.currentPlaylist.addListener(_onPlaylistChanged);
    _playlistService.currentIndex.addListener(_onCurrentIndexChanged);
  }

  /// 初始化协调器
  Future<void> initialize() async {
    await _playlistService.initialize();
    await _settingsManager.init();
    _audioService.initialize();
    debugPrint('PlayerCoordinator: 初始化完成,使用DualAudioService');
  }

  /// 播放音乐
  Future<void> playMusic(Music music) async {
    try {
      // 获取视频详情
      final detailedMusic = await _apiService.getVideoDetails(music.id);

      // 添加到播放列表
      await _playlistService.addToPlaylist(detailedMusic);

      // 设置当前播放索引
      final playlist = _playlistService.currentPlaylist.value;
      final index = playlist.indexWhere(
        (m) => m.id == detailedMusic.id && m.cid == detailedMusic.cid,
      );

      if (index != -1) {
        _playlistService.setCurrentIndex(index);
        await _playCurrentTrack();
      }
    } catch (e) {
      debugPrint('Error playing music: $e');
      rethrow;
    }
  }

  /// 播放当前曲目
  Future<void> _playCurrentTrack() async {
    final music = _playlistService.currentMusic;
    if (music == null) {
      await _audioService.stop();
      return;
    }

    try {
      Music detailedMusic;

      // 如果已有有效的cid,尝试获取对应分P的详情
      if (music.cid.isNotEmpty) {
        detailedMusic = await _apiService.getVideoDetails(
          music.id,
          targetCid: music.cid,
        );
      } else {
        // 否则获取第一个分P的详情
        detailedMusic = await _apiService.getVideoDetails(music.id);
      }

      // 更新通知信息
      _notificationService.updateMediaInfo(detailedMusic);

      // 获取音频URL
      final audioUrl = await _apiService.getAudioUrl(detailedMusic);
      if (audioUrl.isEmpty) {
        throw Exception('Failed to get audio URL');
      }

      // 使用DualAudioService播放
      await _audioService.playActive(audioUrl);

      // 添加到播放历史
      await _playlistService.addToPlayHistory(detailedMusic);

      // 重置预加载状态
      _preloadedMusic = null;

      // 更新通知控制按钮
      _updateNotificationControls();
    } catch (e) {
      debugPrint('Error playing current track: $e');
      await _audioService.stop();
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    await _audioService.pause();
    _updateNotificationControls();
  }

  /// 恢复播放
  Future<void> resume() async {
    await _audioService.resume();
    _updateNotificationControls();
  }

  /// 停止播放
  Future<void> stop() async {
    await _audioService.stop();
    _notificationService.stop();
    _preloadedMusic = null;
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
  }

  /// 切换播放模式
  void togglePlayMode() {
    _audioService.togglePlayMode();
  }

  /// 播放下一首(手动触发,不使用crossfade)
  Future<void> playNext() async {
    // 如果正在crossfade或倒计时中,取消并立即切换
    if (_isCountdownActive || _audioService.isCrossfading) {
      debugPrint('PlayerCoordinator: 取消倒计时/crossfade，执行手动下一首');
      _stopCountdown();
      // 取消crossfade并播放当前曲目
      await _audioService.cancelAndPlay(null);
      await _playCurrentTrack();
      _notificationService.sendCustomEvent({'type': 'next'});
      return;
    }

    // 防抖: 100ms内的多次点击只执行最后一次
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () async {
      final nextIndex = _playlistService.getNextIndex(
        _audioService.playMode.value,
        random: _random,
      );

      if (nextIndex != null) {
        _playlistService.setCurrentIndex(nextIndex);
        // 取消预加载
        _preloadedMusic = null;
        await _playCurrentTrack();
        _notificationService.sendCustomEvent({'type': 'next'});
      }
    });
  }

  /// 播放上一首(手动触发,不使用crossfade)
  Future<void> playPrevious() async {
    // 如果正在crossfade或倒计时中,取消并立即切换
    if (_isCountdownActive || _audioService.isCrossfading) {
      debugPrint('PlayerCoordinator: 取消倒计时/crossfade，执行手动上一首');
      _stopCountdown();
      // 取消crossfade并播放当前曲目
      await _audioService.cancelAndPlay(null);
      await _playCurrentTrack();
      _notificationService.sendCustomEvent({'type': 'previous'});
      return;
    }

    // 防抖
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () async {
      // 如果当前歌曲播放超过3秒,则重新播放当前歌曲
      if (_audioService.currentPosition > const Duration(seconds: 3)) {
        await _audioService.seek(Duration.zero);
        return;
      }

      final previousIndex = _playlistService.getPreviousIndex(
        _audioService.playMode.value,
        random: _random,
      );

      if (previousIndex != null) {
        _playlistService.setCurrentIndex(previousIndex);
        // 取消预加载
        _preloadedMusic = null;
        await _playCurrentTrack();
        _notificationService.sendCustomEvent({'type': 'previous'});
      }
    });
  }

  /// 播放指定索引处的音乐
  Future<void> playAtIndex(int index) async {
    if (index >= 0 && index < _playlistService.playlistLength) {
      _playlistService.setCurrentIndex(index);
      // 取消预加载
      _preloadedMusic = null;
      await _playCurrentTrack();
    }
  }

  /// 添加到播放列表
  Future<void> addToPlaylist(Music music) async {
    await _playlistService.addToPlaylist(music);
  }

  /// 批量添加到播放列表
  Future<void> addAllToPlaylist(List<Music> musics) async {
    await _playlistService.addAllToPlaylist(musics);
  }

  /// 从播放列表移除音乐
  Future<void> removeFromPlaylist(Music music) async {
    await _playlistService.removeFromPlaylist(music);
  }

  /// 清空播放列表
  Future<void> clearPlaylist() async {
    await _playlistService.clearPlaylist();
    await _audioService.stop();
    _preloadedMusic = null;
  }

  /// 在播放列表中移动音乐位置(用于拖拽排序)
  Future<void> moveInPlaylist(int fromIndex, int toIndex) async {
    await _playlistService.moveInPlaylist(fromIndex, toIndex);
  }

  /// 添加到收藏
  Future<void> addToFavorites(Music music) async {
    await _playlistService.addToFavorites(music);
    _updateNotificationControls();
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(Music music) async {
    await _playlistService.removeFromFavorites(music);
    _updateNotificationControls();
  }

  /// 检查是否已收藏
  bool isFavorite(Music music) {
    return _playlistService.isFavorite(music);
  }

  // ============ Crossfade相关方法 ============

  /// 检查预加载触发条件
  void _checkPreloadTrigger() {
    // 基础检查
    if (!_settingsManager.crossfadeEnabled) return;
    if (_audioService.isCrossfading) return;
    if (_isCountdownActive) return; // 防止重复触发
    if (_audioService.playMode.value == PlayMode.loop) return;

    // 检查是否有下一首
    final nextIndex = _playlistService.getNextIndex(
      _audioService.playMode.value,
      random: _random,
    );
    if (nextIndex == null) return;

    final currentDuration = _audioService.currentDuration;
    final currentPosition = _audioService.currentPosition;

    if (currentDuration.inMilliseconds == 0) return;

    final remaining = currentDuration - currentPosition;
    final preloadThreshold = Duration(seconds: _settingsManager.preloadSeconds);

    // 如果剩余时间 <= 预加载阈值
    if (remaining <= preloadThreshold) {
      // 如果standby未就绪且未在预加载中，先预加载
      if (!_audioService.isStandbyReady && !_audioService.isPreloading) {
        debugPrint('PlayerCoordinator: 到达阈值但standby未就绪，先触发预加载');
        _triggerPreload();
      }
      // 如果standby已就绪，启动crossfade
      else if (_audioService.isStandbyReady && !_isCountdownActive) {
        debugPrint('PlayerCoordinator: 到达阈值且standby已就绪，启动基于时间的Crossfade');
        _startTimeBasedCrossfade();
      }
    }
    // 如果距离阈值还有一段距离（提前preloadThreshold + 5秒），且standby未就绪，触发预加载
    else if (remaining <= preloadThreshold + const Duration(seconds: 5) &&
        remaining > preloadThreshold &&
        !_audioService.isStandbyReady &&
        !_audioService.isPreloading) {
      debugPrint('PlayerCoordinator: 提前预加载下一首');
      _triggerPreload();
    }
  }

  /// 启动基于时间的Crossfade切换
  Future<void> _startTimeBasedCrossfade() async {
    if (_isCountdownActive) return;

    debugPrint('PlayerCoordinator: 启动基于时间的Crossfade');

    try {
      // 更新到下一首索引
      final nextIndex = _playlistService.getNextIndex(
        _audioService.playMode.value,
        random: _random,
      );
      if (nextIndex != null) {
        _playlistService.setCurrentIndex(nextIndex);
      }

      // 记录开始时间
      _crossfadeStartTime = DateTime.now();
      _isCountdownActive = true;

      // 启动倒计时定时器（每100ms更新一次）
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _updateCountdownValue();
      });

      // 立即执行crossfade
      await _audioService.executeCrossfade(_settingsManager.crossfadeDuration);

      // crossfade完成后清理
      _preloadedMusic = null;
      final currentMusic = _playlistService.currentMusic;
      if (currentMusic != null) {
        _notificationService.updateMediaInfo(currentMusic);
      }

      _stopCountdown();
      _notificationService.sendCustomEvent({'type': 'trackChanged'});
    } catch (e) {
      debugPrint('PlayerCoordinator: 时间触发Crossfade失败 $e');
      _stopCountdown();
    }
  }

  /// 更新倒计时值
  void _updateCountdownValue() {
    if (_crossfadeStartTime == null) return;

    final elapsed = DateTime.now().difference(_crossfadeStartTime!);
    final duration = Duration(milliseconds: _settingsManager.crossfadeDuration);
    final remaining = duration - elapsed;

    if (remaining.inSeconds <= 0) {
      _crossfadeCountdown.value = 0;
    } else {
      _crossfadeCountdown.value = remaining.inSeconds;
    }
  }

  /// 停止倒计时
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _crossfadeStartTime = null;
    _isCountdownActive = false;
    _crossfadeCountdown.value = -1;
  }

  /// 触发预加载下一首
  Future<void> _triggerPreload() async {
    _audioService.setPreloading(true);

    try {
      // 获取下一首音乐
      final nextIndex = _playlistService.getNextIndex(
        _audioService.playMode.value,
        random: _random,
      );

      if (nextIndex == null) {
        _audioService.setPreloading(false);
        return;
      }

      final playlist = _playlistService.currentPlaylist.value;
      final nextMusic = playlist[nextIndex];

      // 检查是否已经预加载过这首歌
      if (_preloadedMusic != null &&
          _preloadedMusic!.id == nextMusic.id &&
          _preloadedMusic!.cid == nextMusic.cid) {
        _audioService.setPreloading(false);
        return;
      }

      debugPrint('PlayerCoordinator: 开始预加载下一首 ${nextMusic.title}');

      // 获取音频URL
      Music detailedMusic;
      if (nextMusic.cid.isNotEmpty) {
        detailedMusic = await _apiService.getVideoDetails(
          nextMusic.id,
          targetCid: nextMusic.cid,
        );
      } else {
        detailedMusic = await _apiService.getVideoDetails(nextMusic.id);
      }

      final audioUrl = await _apiService.getAudioUrl(detailedMusic);
      if (audioUrl.isEmpty) {
        throw Exception('Failed to get audio URL');
      }

      // 预加载到待命播放器
      await _audioService.preloadToStandby(audioUrl);
      _preloadedMusic = detailedMusic;

      debugPrint('PlayerCoordinator: 预加载成功');
    } catch (e) {
      debugPrint('PlayerCoordinator: 预加载失败 $e');
      _preloadedMusic = null;
    } finally {
      _audioService.setPreloading(false);
    }
  }

  /// 处理播放完成事件
  Future<void> _handlePlaybackCompleted() async {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;

    // 如果正在倒计时中，说明已由时间触发处理完成事件，忽略此回调
    if (_isCountdownActive) {
      debugPrint('PlayerCoordinator: 忽略完成事件（已由时间触发处理）');
      _isHandlingCompletion = false;
      return;
    }

    try {
      // 检查播放列表是否为空
      final playlist = _playlistService.currentPlaylist.value;
      if (playlist.isEmpty) {
        return;
      }

      final playMode = _audioService.playMode.value;

      if (playMode == PlayMode.loop) {
        // 单曲循环:直接重播
        await _audioService.seek(Duration.zero);
        await _audioService.resume();
      } else if (_settingsManager.crossfadeEnabled &&
          _audioService.isStandbyReady) {
        // 启用crossfade且standby就绪:执行无缝切换
        debugPrint('PlayerCoordinator: 执行Crossfade切换');

        // 更新到下一首索引
        final nextIndex = _playlistService.getNextIndex(
          playMode,
          random: _random,
        );
        if (nextIndex != null) {
          _playlistService.setCurrentIndex(nextIndex);
        }

        // 执行crossfade
        await _audioService.executeCrossfade(
          _settingsManager.crossfadeDuration,
        );

        // 更新预加载状态
        _preloadedMusic = null;

        // 更新媒体信息
        final currentMusic = _playlistService.currentMusic;
        if (currentMusic != null) {
          _notificationService.updateMediaInfo(currentMusic);
        }
      } else {
        // 降级:普通切换
        debugPrint('PlayerCoordinator: 降级为普通切换');
        await playNext();
      }

      _notificationService.sendCustomEvent({'type': 'trackChanged'});
    } catch (e) {
      debugPrint('PlayerCoordinator: 处理播放完成失败 $e');
    } finally {
      _isHandlingCompletion = false;
    }
  }

  /// 音频状态变化处理
  void _onAudioStateChanged(AudioState state) {
    _updateNotificationControls();
  }

  /// 播放位置变化处理
  void _onPositionChanged(Duration position) {
    _updateNotificationControls();
    // 检查预加载触发
    _checkPreloadTrigger();
  }

  /// 播放模式变化处理
  void _onPlayModeChanged() {
    _notificationService.sendCustomEvent({
      'type': 'playModeChanged',
      'mode': _audioService.playMode.value.index,
    });
  }

  /// 播放列表变化处理
  void _onPlaylistChanged() {
    _updateNotificationControls();
  }

  /// 当前索引变化处理
  void _onCurrentIndexChanged() {
    _updateNotificationControls();
  }

  /// 更新通知控制按钮
  void _updateNotificationControls() {
    final playlist = _playlistService.currentPlaylist.value;
    final currentIndex = _playlistService.currentIndexSync;
    final currentMusic = _playlistService.currentMusic;

    final controls = _notificationService.getMediaControls(
      hasPlaylist: playlist.isNotEmpty,
      currentIndex: currentIndex,
      playlistLength: playlist.length,
      isPlaying: _audioService.isPlaying,
      isFavorite:
          currentMusic != null && _playlistService.isFavorite(currentMusic),
    );

    _notificationService.updatePlaybackState(
      playing: _audioService.isPlaying,
      position: _audioService.currentPosition,
      controls: controls,
    );
  }

  // ============ Getters ============

  /// 获取当前播放状态
  ValueListenable<AudioState> get state => _audioService.state;

  /// 获取当前播放位置
  ValueListenable<Duration> get position => _audioService.position;

  /// 获取当前音频时长
  ValueListenable<Duration> get duration => _audioService.duration;

  /// 获取当前播放模式
  ValueListenable<PlayMode> get playMode => _audioService.playMode;

  /// 获取当前播放的音乐
  Music? get currentMusic => _playlistService.currentMusic;

  /// 获取播放列表
  ValueListenable<List<Music>> get playlist => _playlistService.currentPlaylist;

  /// 获取播放历史
  ValueListenable<List<Music>> get playHistory => _playlistService.playHistory;

  /// 获取收藏列表
  ValueListenable<List<Music>> get favorites => _playlistService.favorites;

  /// 获取是否正在播放
  bool get isPlaying => _audioService.isPlaying;

  /// 获取当前播放索引
  int? get currentIndex => _playlistService.currentIndexSync;

  /// 获取播放列表长度
  int get playlistLength => _playlistService.playlistLength;

  /// 获取播放进度百分比
  double get progressPercentage => _audioService.progressPercentage;

  /// 获取crossfade状态
  ValueListenable<CrossfadeState> get crossfadeState =>
      _audioService.crossfadeState;

  /// 获取是否正在crossfade
  bool get isCrossfading => _audioService.isCrossfading;

  /// 获取crossfade倒计时（秒），-1表示未激活
  ValueListenable<int> get crossfadeCountdown => _crossfadeCountdown;

  /// 释放资源
  Future<void> dispose() async {
    _audioService.onPlaybackCompleted = null;
    _audioService.onPositionChanged = null;
    _audioService.onStateChanged = null;

    _audioService.playMode.removeListener(_onPlayModeChanged);
    _playlistService.currentPlaylist.removeListener(_onPlaylistChanged);
    _playlistService.currentIndex.removeListener(_onCurrentIndexChanged);

    _debounceTimer?.cancel();
    _countdownTimer?.cancel();
    _crossfadeCountdown.dispose();
    await _audioService.dispose();
    await _playlistService.dispose();
  }
}
