import 'dart:async';
import 'dart:math';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/models/roam_style.dart';
import 'package:flutter/foundation.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/services/notification_service.dart';
import 'package:bilimusic/services/api_service.dart';
import 'package:bilimusic/services/roaming_service.dart';
import 'package:bilimusic/managers/settings_manager.dart';

/// 漫游会话：进入 roam 时创建，退出 roam 时置 null。
///
/// 与 [PlayMode] 完全正交——roam 期间 PlayMode 不变（用户可继续按 sequential/
/// shuffle 播）。退出 roam 只清空本会话，队列保留。
class _RoamSession {
  final RoamStyle style;
  final int refillThreshold;
  final List<Music> seeds;

  const _RoamSession({
    required this.style,
    required this.refillThreshold,
    this.seeds = const [],
  });
}

/// 播放器协调器
/// 职责: 协调各个服务的工作,提供统一的播放器接口,管理双播放器的切换和预加载
class PlayerCoordinator {
  final DualAudioService _audioService;
  final SettingsManager _settingsManager;
  final PlaylistService _playlistService;
  final NotificationService _notificationService;
  final ApiService _apiService;
  final RoamingService _roamingService;

  final Random _random = Random();
  bool _isHandlingCompletion = false;
  Timer? _debounceTimer;
  Timer? _countdownTimer; // 倒计时定时器
  DateTime? _crossfadeStartTime; // crossfade开始时间戳
  bool _isCountdownActive = false; // 防止重复触发
  bool _isPreloading = false; // 预加载中（coordinator 侧）
  Music? _preloadedMusic; // 记录已预加载的音乐
  int? _preloadedIndex; // 记录已预加载的音乐索引

  // 漫游状态机：与 PlayMode 正交，由 profile_page 单独控制进入/退出
  _RoamSession? _roamSession;
  bool _roamFetchInFlight = false;

  PlayerCoordinator({
    required DualAudioService audioService,
    required SettingsManager settingsManager,
    required PlaylistService playlistService,
    required NotificationService notificationService,
    required ApiService apiService,
    required RoamingService roamingService,
  }) : _audioService = audioService,
       _settingsManager = settingsManager,
       _playlistService = playlistService,
       _notificationService = notificationService,
       _apiService = apiService,
       _roamingService = roamingService {
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
    debugPrint('[PlayerCoordinator] 初始化完成');
  }

  /// 播放音乐
  ///
  /// 唯一性流程：
  /// 1. 若 cid 缺失，调 [_apiService.ensureCid] 补齐（同时刷新元信息）。
  /// 2. 在当前播放列表里按 (bvid, cid) 查重：
  ///    - 命中 → 直接选中已有项播放。
  ///    - 未命中 → 先 addToPlaylist，再选中新增项播放。
  Future<void> playMusic(Music music) async {
    try {
      final candidate = music.cid.isEmpty
          ? await _apiService.ensureCid(music)
          : music;

      var idx = _playlistService.currentPlaylist.value.indexWhere(
        (m) => m.id == candidate.id && m.cid == candidate.cid,
      );

      if (idx == -1) {
        await _playlistService.addToPlaylist(candidate);
        idx = _playlistService.currentPlaylist.value.indexWhere(
          (m) => m.id == candidate.id && m.cid == candidate.cid,
        );
        if (idx == -1) return;
      }

      _playlistService.setCurrentIndex(idx);
      await _playCurrentTrack();
    } catch (e) {
      debugPrint('[PlayerCoordinator] Error playing music: $e');
      rethrow;
    }
  }

  /// 暴露 [ApiService.ensureCid] 给 PlaylistService 在加载时回填缺失 cid。
  Future<Music> ensureCid(Music music) => _apiService.ensureCid(music);

  /// 播放当前索引处的曲目。
  ///
  /// `_playCurrentTrack` 的 public 转发，供 onboarding apply 步骤调用。
  Future<void> playCurrentTrack() => _playCurrentTrack();

  /// 播放当前曲目
  Future<void> _playCurrentTrack() async {
    Music? music = _playlistService.currentMusic;
    if (music == null) {
      await _audioService.stop();
      return;
    }

    try {
      Music detailedMusic;

      // 仅在 cid 缺失时回填。已有 cid + 已有 audioUrl 的稳定 fast-path 不再走网络。
      if (music.cid.isEmpty) {
        detailedMusic = await _apiService.ensureCid(music);
        if (detailedMusic.cid.isNotEmpty) {
          await _playlistService.updateToPlaylist(detailedMusic);
        }
      } else {
        detailedMusic = music;
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
      _preloadedIndex = null;

      // 更新通知控制按钮
      _updateNotificationControls();
    } catch (e) {
      debugPrint('[PlayerCoordinator] Error playing current track: $e');
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
    _preloadedIndex = null;
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
  }

  /// 切换播放模式
  void togglePlayMode() {
    _audioService.togglePlayMode();
  }

  /// 显式设置播放模式（与 togglePlayMode 互不影响）。
  ///
  /// 仅接受 [PlayMode] 中的值；漫游模式由 [startRoam]/[stopRoam] 控制，
  /// 不通过 [setPlayMode] 进入或退出。
  void setPlayMode(PlayMode mode) {
    _audioService.setPlayMode(mode);
  }

  /// 播放下一首(手动触发,不使用crossfade)
  Future<void> playNext() async {
    // 如果正在crossfade或倒计时中,取消并立即切换
    if (_isCountdownActive || _audioService.isFading) {
      debugPrint('[PlayerCoordinator] 取消倒计时/crossfade，执行手动下一首');
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
        _preloadedIndex = null;
        await _playCurrentTrack();
        _notificationService.sendCustomEvent({'type': 'next'});
      }
    });
  }

  /// 播放上一首(手动触发,不使用crossfade)
  Future<void> playPrevious() async {
    // 如果正在crossfade或倒计时中,取消并立即切换
    if (_isCountdownActive || _audioService.isFading) {
      debugPrint('[PlayerCoordinator] 取消倒计时/crossfade，执行手动上一首');
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
        _preloadedIndex = null;
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
      _preloadedIndex = null;
      await _playCurrentTrack();
    }
  }

  /// 将音乐作为下一首放入播放列表
  /// - 若当前无正在播放歌曲：直接播放（复用 playMusic 的查重+播放逻辑）
  /// - 否则：将音乐插入/移至 currentIndex+1 位置，不自动播放
  Future<void> playNextFromIndex(Music music) async {
    final currentMusic = _playlistService.currentMusic;
    if (currentMusic == null) {
      await playMusic(music);
      return;
    }

    final currentIndex = _playlistService.currentIndexSync!;

    await _playlistService.addToPlaylist(music);

    final playlist = _playlistService.currentPlaylist.value;
    final newIndex = playlist.indexWhere(
      (m) => m.id == music.id && m.cid == music.cid,
    );
    if (newIndex == -1) return;

    await _playlistService.moveInPlaylist(newIndex, currentIndex + 1);
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
    _preloadedIndex = null;
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
    if (_audioService.isFading) return;
    if (_isCountdownActive) return; // 防止重复触发

    // 检查是否有下一首（优先使用预加载的索引）
    final hasNext =
        _preloadedIndex != null ||
        _playlistService.getNextIndex(
              _audioService.playMode.value,
              random: _random,
            ) !=
            null;
    if (!hasNext) return;

    final currentDuration = _audioService.currentDuration;
    final currentPosition = _audioService.currentPosition;

    if (currentDuration.inMilliseconds == 0) return;

    final remaining = currentDuration - currentPosition;
    final preloadThreshold = Duration(seconds: _settingsManager.preloadSeconds);

    // 如果剩余时间 <= 预加载阈值
    if (remaining <= preloadThreshold) {
      // 如果standby未就绪且未在预加载中，先预加载
      if (!_audioService.isStandbyReady && !_isPreloading) {
        debugPrint('[PlayerCoordinator] 到达阈值但standby未就绪，先触发预加载');
        _triggerPreload();
      }
      // 如果standby已就绪，启动crossfade
      else if (_audioService.isStandbyReady && !_isCountdownActive) {
        if (!_settingsManager.autoPlayNext) return;
        debugPrint('[PlayerCoordinator] 到达阈值且standby已就绪，启动基于时间的Crossfade');
        _startTimeBasedCrossfade();
      }
    }
    // 如果距离阈值还有一段距离（提前preloadThreshold + 5秒），且standby未就绪，触发预加载
    else if (remaining <= preloadThreshold + const Duration(seconds: 5) &&
        remaining > preloadThreshold &&
        !_audioService.isStandbyReady &&
        !_isPreloading) {
      debugPrint('[PlayerCoordinator] 提前预加载下一首');
      _triggerPreload();
    }
  }

  /// 启动基于时间的Crossfade切换
  Future<void> _startTimeBasedCrossfade() async {
    if (_isCountdownActive) return;

    debugPrint('[PlayerCoordinator] 启动基于时间的Crossfade');

    try {
      // 使用预加载的索引，确保预加载和 crossfade 的歌曲一致
      final nextIndex =
          _preloadedIndex ??
          _playlistService.getNextIndex(
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
      _preloadedIndex = null;
      final currentMusic = _playlistService.currentMusic;
      if (currentMusic != null) {
        _notificationService.updateMediaInfo(currentMusic);
        await _playlistService.addToPlayHistory(currentMusic);
      }

      _stopCountdown();
      _notificationService.sendCustomEvent({'type': 'trackChanged'});
    } catch (e) {
      debugPrint('[PlayerCoordinator] 时间触发Crossfade失败 $e');
      _stopCountdown();
    }
  }

  /// 更新倒计时值
  void _updateCountdownValue() {
    if (_crossfadeStartTime == null) return;

    final elapsed = DateTime.now().difference(_crossfadeStartTime!);
    final duration = Duration(milliseconds: _settingsManager.crossfadeDuration);
    final remaining = duration - elapsed;

    final secs = remaining.inSeconds <= 0 ? 0 : remaining.inSeconds;
    _audioService.setPlayerState(PlayerPlaying(fadeCountdown: secs));
  }

  /// 停止倒计时
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _crossfadeStartTime = null;
    _isCountdownActive = false;
    // 清掉 fade 子态
    if (_audioService.playerState.value is PlayerPlaying) {
      _audioService.setPlayerState(PlayerPlaying());
    }
  }

  /// 触发预加载下一首
  Future<void> _triggerPreload() async {
    _isPreloading = true;

    try {
      // 获取下一首音乐
      final nextIndex = _playlistService.getNextIndex(
        _audioService.playMode.value,
        random: _random,
      );

      if (nextIndex == null) {
        return;
      }

      final playlist = _playlistService.currentPlaylist.value;
      final nextMusic = playlist[nextIndex];

      // 检查是否已经预加载过这首歌
      if (_preloadedMusic != null &&
          _preloadedMusic!.id == nextMusic.id &&
          _preloadedMusic!.cid == nextMusic.cid) {
        return;
      }

      debugPrint('[PlayerCoordinator] 开始预加载下一首 ${nextMusic.title}');

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
      _preloadedIndex = nextIndex;

      debugPrint('[PlayerCoordinator] 预加载成功');
    } catch (e) {
      debugPrint('[PlayerCoordinator] 预加载失败 $e');
      _preloadedMusic = null;
      _preloadedIndex = null;
    } finally {
      _isPreloading = false;
    }
  }

  /// 处理播放完成事件
  Future<void> _handlePlaybackCompleted() async {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;

    // 如果正在倒计时中，说明已由时间触发处理完成事件，忽略此回调
    if (_isCountdownActive) {
      debugPrint('[PlayerCoordinator] 忽略完成事件（已由时间触发处理）');
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
        if (!_settingsManager.autoPlayNext) return;
        debugPrint('[PlayerCoordinator] 执行Crossfade切换');

        // 使用预加载的索引，确保预加载和 crossfade 的歌曲一致
        final nextIndex =
            _preloadedIndex ??
            _playlistService.getNextIndex(playMode, random: _random);
        if (nextIndex != null) {
          _playlistService.setCurrentIndex(nextIndex);
        }

        // 执行crossfade
        await _audioService.executeCrossfade(
          _settingsManager.crossfadeDuration,
        );

        // 更新预加载状态
        _preloadedMusic = null;
        _preloadedIndex = null;

        // 更新媒体信息
        final currentMusic = _playlistService.currentMusic;
        if (currentMusic != null) {
          _notificationService.updateMediaInfo(currentMusic);
          await _playlistService.addToPlayHistory(currentMusic);
        }
      } else {
        // 降级:普通切换
        if (!_settingsManager.autoPlayNext) return;
        debugPrint('[PlayerCoordinator] 降级为普通切换');
        await playNext();
      }

      _notificationService.sendCustomEvent({'type': 'trackChanged'});
    } catch (e) {
      debugPrint('[PlayerCoordinator] 处理播放完成失败 $e');
    } finally {
      _isHandlingCompletion = false;
    }
  }

  // ============ Roam 相关方法 ============

  /// 进入漫游模式：以 [playlistId] 歌单为种子，清空当前队列后从首曲开始播放，
  /// 后续按 [_checkRoamRefill] 懒加载相关歌曲。
  ///
  /// 行为：
  /// - 清空当前播放列表（接受丢失当前进度，符合 网易云/Spotify RF 的 UX）
  /// - 加载歌单所有歌曲（系统 favorites / 用户自建歌单）
  /// - 从 currentIndex = 0 开始播放
  /// - 创建 [_RoamSession] 激活懒加载
  ///
  /// 空歌单保护：歌单为空时直接 return，不创建 session、不抛错。
  Future<void> startRoam(String playlistId, RoamStyle style) async {
    // 先停掉当前播放（防 crossfade 残留状态污染新队列）
    await _audioService.stop();
    _preloadedMusic = null;
    _preloadedIndex = null;
    await clearPlaylist();

    // 加载种子歌曲
    final List<Music> seeds;
    if (playlistId == 'favorites') {
      seeds = await _playlistService.getSystemPlaylistSongs('favorites');
    } else {
      seeds = await _playlistService.loadPlaylistSongs(playlistId);
    }
    if (seeds.isEmpty) {
      debugPrint('[PlayerCoordinator] startRoam: empty playlist $playlistId');
      return;
    }

    await _playlistService.addAllToPlaylist(seeds);
    _playlistService.setCurrentIndex(0);

    _roamSession = _RoamSession(
      style: style,
      refillThreshold: _settingsManager.roamRefillThreshold,
      seeds: seeds,
    );

    await _playCurrentTrack();
    debugPrint(
      '[PlayerCoordinator] roam started from $playlistId, style=$style',
    );
  }

  /// 应用漫游播放列表（供 onboarding 完成步骤使用）。
  ///
  /// 与 [startRoam] 的区别：
  /// - 不再从歌单加载种子，调用方已准备好完整播放列表 [songs]（种子 + 推荐 shuffle 后）。
  /// - 显式传入用户挑选的 [seeds]（数量 = 1 或 3），用于续杯时的多种子拉取。
  Future<void> applyRoamPlaylist({
    required List<Music> songs,
    required RoamStyle style,
    required List<Music> seeds,
  }) async {
    // 先停掉当前播放（防 crossfade 残留状态污染新队列）
    await _audioService.stop();
    _preloadedMusic = null;
    _preloadedIndex = null;
    await clearPlaylist();

    if (songs.isEmpty) {
      debugPrint('[PlayerCoordinator] applyRoamPlaylist: empty songs');
      return;
    }

    await _playlistService.addAllToPlaylist(songs);
    _playlistService.setCurrentIndex(0);

    _roamSession = _RoamSession(
      style: style,
      refillThreshold: _settingsManager.roamRefillThreshold,
      seeds: seeds,
    );

    await _playCurrentTrack();
    debugPrint(
      '[PlayerCoordinator] roam applied: ${songs.length} songs, ${seeds.length} seeds, style=$style',
    );
  }

  /// 退出漫游模式：停用 session，队列保留并继续按当前 PlayMode 播。
  void stopRoam() {
    if (_roamSession == null) return;
    _roamSession = null;
    debugPrint('[PlayerCoordinator] roam stopped');
  }

  /// 检查队列余量，触发 roam 懒加载。
  ///
  /// 由 [_onCurrentIndexChanged] 在每次曲目切换时调用。
  /// 也可在 startRoam 后立即调一次（用户切换歌单后立刻预填）。
  void _checkRoamRefill() {
    final session = _roamSession;
    if (session == null || _roamFetchInFlight) return;
    final idx = _playlistService.currentIndexSync;
    if (idx == null) return;

    final playlist = _playlistService.currentPlaylist.value;
    final remaining = playlist.length - idx - 1;
    if (remaining < session.refillThreshold) {
      _triggerRoamFetch();
    }
  }

  /// 拉一批候选歌曲并追加到当前队列。
  ///
  /// 多种子 refill：
  /// - 主种子 = 当前播放的歌曲
  /// - 副种子 = 从 session.seeds 中随机抽 1 颗（避免与当前曲重复）
  /// - 两个种子并发 fetchBatch(size: 2) → 合并 → shuffle → take 4
  /// - `_roamFetchInFlight` 防重入
  /// - 失败 / 0 候选：debugPrint 留痕，下次 currentIndex 变化再用新 seed 重试
  Future<void> _triggerRoamFetch() async {
    final session = _roamSession;
    final current = _playlistService.currentMusic;
    if (session == null || current == null) return;

    // 副种子：从 session.seeds 中随机抽 1 颗（剔除与 currentMusic 同 id 的）
    final pool = session.seeds.where((s) => s.id != current.id).toList();
    final companion = pool.isNotEmpty
        ? pool[_random.nextInt(pool.length)]
        : null;
    final seeds = companion != null && companion.id != current.id
        ? [current, companion]
        : [current];

    _roamFetchInFlight = true;
    try {
      final futures = seeds.map(
        (s) =>
            _roamingService.fetchBatch(seed: s, style: session.style, size: 2),
      );
      final batches = await Future.wait(futures);
      final merged = batches.expand((l) => l).toList()..shuffle(_random);
      final unique = _dedupByIdCid(merged).take(4).toList();
      if (unique.isNotEmpty) {
        await _playlistService.addAllToPlaylist(unique);
        debugPrint(
          '[PlayerCoordinator] roam refilled +${unique.length} (seeds=${seeds.length}, style=${session.style.name})',
        );
      } else {
        debugPrint('[PlayerCoordinator] roam refill: 0 candidates');
      }
    } catch (e) {
      debugPrint('[PlayerCoordinator] roam refill failed: $e');
    } finally {
      _roamFetchInFlight = false;
    }
  }

  /// 按 (id, cid) 去重。
  List<Music> _dedupByIdCid(List<Music> list) {
    final seen = <String>{};
    final out = <Music>[];
    for (final m in list) {
      final key = '${m.id}_${m.cid}';
      if (seen.add(key)) out.add(m);
    }
    return out;
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
    // 每次曲目切换都检查队列余量，触发 roam refill（如果激活）
    _checkRoamRefill();
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

  /// 获取当前播放状态（PlayerState sealed class）
  ValueListenable<PlayerState> get playerState => _audioService.playerState;

  /// 获取当前播放位置
  ValueListenable<Duration> get position => _audioService.position;

  /// 获取当前音频时长
  ValueListenable<Duration> get duration => _audioService.duration;

  /// 获取当前播放模式
  ValueListenable<PlayMode> get playMode => _audioService.playMode;

  /// 当前是否处于漫游模式。
  bool get isRoaming => _roamSession != null;

  /// 当前漫游会话的风格档位。
  RoamStyle? get roamStyle => _roamSession?.style;

  /// 当前漫游会话的续杯阈值（仅当 [isRoaming] 为 true 时有意义）。
  int? get roamRefillThreshold => _roamSession?.refillThreshold;

  /// 当前漫游会话的用户挑选种子（1 颗 lowData / 3 颗 normal）。
  ///
  /// 仅当 [isRoaming] 为 true 时有意义。用于续杯的多种子拉取。
  List<Music> get roamSeeds => _roamSession?.seeds ?? const [];

  /// 获取当前播放的音乐
  Music? get currentMusic => _playlistService.currentMusic;

  /// 获取播放列表
  ValueListenable<List<Music>> get playlist => _playlistService.currentPlaylist;

  /// 当前播放索引（ValueListenable，用于监听切歌）
  ValueListenable<int?> get currentIndexNotifier =>
      _playlistService.currentIndex;

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
    await _audioService.dispose();
    await _playlistService.dispose();
  }
}
