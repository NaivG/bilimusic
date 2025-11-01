import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'player_manager.dart';
import 'package:bilimusic/utils/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
// import 'package:just_aaudio/just_aaudio.dart';
import 'package:bilimusic/utils/settings_manager.dart';

class AudioPlayerManager extends PlayerManager {
  final List<StreamSubscription> _subscriptions = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  late BaseAudioHandler _audioHandler; // 新增

  final List<model.Music> _playList = [];
  final List<model.Music> _playHistory = []; // 新增播放历史记录
  final List<model.Music> _favorites = []; // 收藏列表
  int _currentTrackIndex = -1;
  PlayMode _playMode = PlayMode.sequential;

  AudioState _currentState = AudioState.stopped;

  // 播放状态变化监听器列表
  final List<Function(AudioState)> _stateListeners = [];

  // 播放位置变化监听器列表
  final List<Function(Duration)> _positionListeners = [];

  // 是否正在处理播放完成事件
  bool _isHandlingCompletion = false;
  
  // SharedPreferences实例
  SharedPreferences? _prefs;

  AudioPlayerManager();

  @override
  bool get isPlaying => _currentState != AudioState.stopped;

  /// 设置AudioHandler
  void setAudioHandler(BaseAudioHandler handler) async {
    _prefs = await SharedPreferences.getInstance();
    _getSavedPlayList();
    _getPlayHistory();
    _getFavorites();
    _audioHandler = handler;
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    // 仅在安卓平台上设置音频输出模式
    // if (!Platform.isAndroid) {
    //   _audioPlayer.setPlayerType(PlayerType.justAudio);
    // } else {
    //   // 根据设置选择音频输出模式
    //   final settings = SettingsManager();
    //   _audioPlayer.setPlayerType(PlayerType.aaudio);
    // }
    
    // 创建播放状态变化监听器
    final playerStateSubscription = _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = _convertProcessingState(playerState.processingState);

      if (processingState == AudioProcessingState.completed) {
        _handlePlaybackCompleted();
      }

      _currentState = isPlaying ? AudioState.playing : AudioState.paused;
      _notifyStateListeners(_currentState);

      // 更新媒体通知播放状态
      _audioHandler.playbackState.add(PlaybackState(
        controls: _getMediaControls(),
        playing: isPlaying,
        updatePosition: _audioPlayer.position,
        bufferedPosition: _audioPlayer.bufferedPosition ?? Duration.zero,
        speed: _audioPlayer.speed,
        processingState: processingState,
      ));
    }, onError: (error) {
      debugPrint("Audio player state stream error: $error");
    });

    // 创建播放位置变化监听器
    final positionSubscription = _audioPlayer.positionStream.listen((position) {
      _notifyPositionListeners(position);

      // 更新媒体通知位置
      _audioHandler.playbackState.add(PlaybackState(
        controls: _getMediaControls(),
        playing: _audioPlayer.playing,
        updatePosition: position,
        bufferedPosition: _audioPlayer.bufferedPosition ?? Duration.zero,
        speed: _audioPlayer.speed,
        processingState: _convertProcessingState(_audioPlayer.playerState.processingState),
        androidCompactActionIndices: const [0, 1, 3],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
      ));
    }, onError: (error) {
      debugPrint("Audio player position stream error: $error");
    });

    // 添加订阅到列表以便后续释放
    _subscriptions.add(playerStateSubscription);
    _subscriptions.add(positionSubscription);

    // 初始化媒体通知状态
    _audioHandler.playbackState.add(PlaybackState(
      controls: _getMediaControls(),
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
      processingState: AudioProcessingState.idle,
    ));
  }

  /// 将JustAudio的ProcessingState转换为AudioService的AudioProcessingState
  AudioProcessingState _convertProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.buffering;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      }
  }

  List<MediaControl> _getMediaControls() {
    // 当播放列表为空时返回空列表
    if (_playList.isEmpty) {
      return [];
    }

    // 当播放列表不为空但当前索引无效时返回基本控件
    if (_currentTrackIndex < 0 || _currentTrackIndex >= _playList.length) {
      return [
        MediaControl.play,
      ];
    }

    return [
      MediaControl.skipToPrevious,
      if (_audioPlayer.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl(
        androidIcon: 'drawable/ic_favorite',
        label: '收藏',
        action: MediaAction.custom,
        customAction: const CustomMediaAction(name: 'favorite'),
      ),
    ];
  }

  void _handlePlaybackCompleted() {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;

    // 根据播放模式处理下一首
    switch (_playMode) {
      case PlayMode.sequential:
        playNext();
        break;
      case PlayMode.loop:
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.play();
        break;
      case PlayMode.shuffle:
        playNext();
        break;
    }
    // 发送自定义事件到媒体通知
    _audioHandler.customEvent.add({'type': 'trackChanged'});

    _isHandlingCompletion = false;
  }

  @override
  AudioState get currentState => _currentState;

  @override
  model.Music? get currentMusic {
    if (_currentTrackIndex >= 0 && _currentTrackIndex < _playList.length) {
      return _playList[_currentTrackIndex];
    }
    return null;
  }

  @override
  List<model.Music> get playList => List<model.Music>.from(_playList);
  
  // 获取播放历史记录
  List<model.Music> get playHistory => List<model.Music>.from(_playHistory);

  // 获取收藏列表
  List<model.Music> get favorites => List<model.Music>.from(_favorites);

  @override
  PlayMode get playMode => _playMode;

  @override
  Future<void> play(model.Music music) async {
    // 查找音乐是否已经在播放列表中
    final index = _playList.indexWhere((m) => m.id == music.id);

    if (index != -1) {
      // 如果是当前正在播放的曲目，且分P一致，则直接返回
      if (index == _currentTrackIndex &&
          _currentState == AudioState.playing &&
          _playList[index].pages.isNotEmpty &&
          music.pages.isNotEmpty &&
          _playList[index].pages[0].cid != null &&
          music.pages[0].cid != null &&
          _playList[index].pages[0].cid == music.pages[0].cid) {
        return;
      }
      _currentTrackIndex = index;
    } else {
      // 否则添加到播放列表并设置为当前曲目
      await addToPlayList(music);
      _currentTrackIndex = _playList.length - 1;
    }

    await _playCurrentTrack();
    // 添加到播放历史记录
    _addToPlayHistory(_playList[_currentTrackIndex]);
  }

  Future<void> _playCurrentTrack() async {
    if (_currentTrackIndex < 0 || _currentTrackIndex >= _playList.length) {
      _currentState = AudioState.stopped;
      _notifyStateListeners(_currentState);
      return;
    }

    try {
      _currentState = AudioState.buffering;
      _notifyStateListeners(_currentState);

      final music = _playList[_currentTrackIndex];
      // 提前更新媒体通知，使用当前音乐信息
      _updateMediaNotification(music); // 提前调用

      final audioUrl = await _getAudioUrl(music);

      if (audioUrl.isEmpty) {
        _currentState = AudioState.stopped;
        _notifyStateListeners(_currentState);
        return;
      }

      await _audioPlayer.setFilePath(audioUrl);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();

      // 如果duration为空，触发视频详情获取（这可能会在后台更新音乐信息，但不影响当前通知）
      if (music.duration == null || music.duration!.inSeconds < 10) {
        final detailedMusic = await music.getVideoDetails();
        _playList[_currentTrackIndex] = detailedMusic;
        // 如果获取到更详细的音乐信息，再次更新通知
        _updateMediaNotification(detailedMusic);
        _notifyStateListeners(_currentState);
      }

      _currentState = AudioState.playing;
      _notifyStateListeners(_currentState);

      _audioHandler.customEvent.add({'type': 'trackChanged'});
    } catch (e) {
      _currentState = AudioState.stopped;
      _notifyStateListeners(_currentState);
      debugPrint('Error playing music: $e');
    }
  }

  Future<String> _getAudioUrl(model.Music music) async {
    try {
      // 首先检查音乐是否已缓存
      String cacheKey = music.id;
      if (music.pages.isNotEmpty) {
        cacheKey = "${music.id}_${music.pages[0].cid}";
      }

      final cachedFile = await musicCacheManager.getFileFromCache(cacheKey);
      if (cachedFile != null) {
        return cachedFile.file.path;
      }

      // 如果没有缓存，从网络获取
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=${music.id}'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data']['pages'] != null &&
            json['data']['pages'].isNotEmpty) {
          // 解析所有分P信息
          final pagesList = (json['data']['pages'] as List)
              .map((pageJson) => model.Page.fromJson(pageJson))
              .toList();

          // 更新music的pages信息（在后台更新，不影响当前播放）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // 创建新的Music对象包含更新的pages
            final detailedMusic = model.Music(
              id: music.id,
              title: music.title,
              artist: music.artist,
              album: music.album,
              coverUrl: music.coverUrl,
              duration: music.duration ?? Duration(
                  seconds: int.tryParse(json['data']['duration']) ?? 180),
              audioUrl: music.audioUrl,
              pages: pagesList,
              isFavorite: music.isFavorite, // 保持收藏状态
            );
            // 更新播放列表中的音乐信息
            if (_currentTrackIndex >= 0 &&
                _currentTrackIndex < _playList.length) {
              _playList[_currentTrackIndex] = detailedMusic;
            }
          });

          // 获取CID - 优先使用当前Music对象的CID，否则使用第一个分P的CID
          String cid;
          if (music.pages.isNotEmpty) {
            // 当前Music对象已经包含特定分P信息时，使用其CID
            cid = music.pages[0].cid;
          } else {
            // 否则使用API返回的第一个分P的CID
            cid = pagesList.isNotEmpty ? pagesList[0].cid : json['data']['cid']
                ?.toString() ?? '';
          }

          final audioResponse = await http.get(
            Uri.parse('https://api.bilibili.com/x/player/playurl?bvid=${music
                .id}&cid=$cid&fnval=16'),
            headers: NetworkConfig.biliHeaders,
          );

          if (audioResponse.statusCode == 200) {
            final audioJson = jsonDecode(audioResponse.body);

            if (audioJson['code'] == 0 &&
                audioJson['data'] != null &&
                audioJson['data']['dash'] != null &&
                audioJson['data']['dash']['audio'] != null &&
                audioJson['data']['dash']['audio'].isNotEmpty) {
              // 下载并缓存音频文件
              final audioUrl = audioJson['data']['dash']['audio'][0]['baseUrl'];

              // 使用cacheManager下载并缓存文件，添加CID到缓存键中
              final file = await musicCacheManager.downloadFile(
                audioUrl,
                key: "${music.id}_$cid",
                authHeaders: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
                  'Referer': 'https://www.bilibili.com'
                },
              );
              return file.file.path;
            }
          }
        }
      }

      // 如果获取失败，尝试备用方案或返回空字符串
      debugPrint('Failed to get audio URL for ${music.id}');
      return '';
    } catch (e, stackTrace) {
      debugPrint('Error getting audio URL for ${music.id}: $e');
      debugPrint('Stack trace: $stackTrace');
      return '';
    }
  }

  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
    _currentState = AudioState.paused;
    _notifyStateListeners(_currentState);
    // 更新媒体通知状态 - 使用AudioHandler
    _audioHandler.playbackState.add(PlaybackState(
      controls: _getMediaControls(),
      playing: false,
      updatePosition: _audioPlayer.position,
      bufferedPosition: _audioPlayer.bufferedPosition ?? Duration.zero,
      speed: _audioPlayer.speed,
      processingState: _convertProcessingState(_audioPlayer.playerState.processingState),
    ));
  }

  @override
  Future<void> resume() async {
    await _audioPlayer.play();
    _currentState = AudioState.playing;
    _notifyStateListeners(_currentState);
    // 更新媒体通知状态 - 使用AudioHandler
    _audioHandler.playbackState.add(PlaybackState(
      controls: _getMediaControls(),
      playing: true,
      updatePosition: _audioPlayer.position,
      bufferedPosition: _audioPlayer.bufferedPosition ?? Duration.zero,
      speed: _audioPlayer.speed,
      processingState: _convertProcessingState(_audioPlayer.playerState.processingState),
    ));
  }

  // 停止播放并释放音频资源
  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentState = AudioState.stopped;
    _notifyStateListeners(_currentState);
    // 清理媒体通知
    // await AudioService.stop();
    // await _audioHandler.stop(); // 本身_audioHandler会直接调用stop，所以这里不需要再调用了
  }

  @override
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  // 切换播放模式
  @override
  Future<void> togglePlayMode() async {
    _playMode = PlayMode.values[(_playMode.index + 1) % PlayMode.values.length];
    // 更新媒体通知播放模式
    _audioHandler.customEvent.add({'type': 'playModeChanged', 'mode': _playMode.index});
    _notifyStateListeners(_currentState);
  }

  /// 将单个音乐添加到播放列表，并保存到持久化存储
  @override
  Future<void> addToPlayList(model.Music music) async {
    if (!_playList.any((m) =>
        m.id == music.id &&
        (m.pages.isEmpty && music.pages.isEmpty ||
            m.pages.isNotEmpty && music.pages.isNotEmpty &&
                m.pages[0].cid == music.pages[0].cid))) {
      _playList.add(music);
      await _savePlayList(); // 保存到持久化存储
    }
  }

  @override
  Future<void> addAllToPlayList(List<model.Music> musics) async {
    final newMusics = musics.where((music) =>
        !_playList.any((m) =>
        m.id == music.id &&
        (m.pages.isEmpty && music.pages.isEmpty ||
            m.pages.isNotEmpty && music.pages.isNotEmpty &&
                m.pages[0].cid == music.pages[0].cid)));

    if (newMusics.isNotEmpty) {
      _playList.addAll(newMusics);
      await _savePlayList(); // 保存到持久化存储
    }
  }

  /// 从播放列表中移除指定音乐
  @override
  Future<void> removeFromPlayList(model.Music music) async {
    final index = _playList.indexWhere((m) =>
        m.id == music.id &&
        (m.pages.isEmpty && music.pages.isEmpty ||
            m.pages.isNotEmpty && music.pages.isNotEmpty &&
                m.pages[0].cid == music.pages[0].cid));

    if (index != -1) {
      _playList.removeAt(index);
      
      // 如果移除的是当前正在播放的歌曲，则调整当前索引
      if (index == _currentTrackIndex) {
        if (_playList.isNotEmpty) {
          _currentTrackIndex = index < _playList.length ? index : _playList.length - 1;
          if (_currentState == AudioState.playing) {
            await _playCurrentTrack();
          }
        } else {
          _currentTrackIndex = -1;
          await stop();
        }
      } else if (index < _currentTrackIndex) {
        // 如果移除的歌曲在当前播放歌曲之前，需要调整当前索引
        _currentTrackIndex--;
      }
      
      await _savePlayList(); // 保存到持久化存储
    }
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
  Future<void> clearPlayList() async {
    await stop();
    _playList.clear();
    _currentTrackIndex = -1;
    await _clearSavedPlayList(); // 清除持久化存储的播放列表
  }

  /// 将音乐插入到当前播放音乐的下一首位置
  Future<void> playNextFromIndex(model.Music music) async {
    // 检查音乐是否已经在播放列表中
    final existingIndex = _playList.indexWhere((m) =>
        m.id == music.id &&
        (m.pages.isEmpty && music.pages.isEmpty ||
            m.pages.isNotEmpty && music.pages.isNotEmpty &&
                m.pages[0].cid == music.pages[0].cid));

    if (existingIndex >= 0) {
      // 如果音乐已在播放列表中，将其移动到当前播放音乐的下一首位置
      final musicToMove = _playList[existingIndex];
      _playList.removeAt(existingIndex);
      
      // 计算插入位置
      int insertIndex = _currentTrackIndex + 1;
      if (insertIndex > _playList.length) {
        insertIndex = _playList.length;
      }
      
      _playList.insert(insertIndex, musicToMove);
      
      // 如果移除的元素在当前播放索引之前，需要调整当前播放索引
      if (existingIndex < _currentTrackIndex) {
        _currentTrackIndex--;
      }
    } else {
      // 如果音乐不在播放列表中，将其插入到当前播放音乐的下一首位置
      int insertIndex = _currentTrackIndex + 1;
      if (insertIndex > _playList.length) {
        insertIndex = _playList.length;
      }
      
      _playList.insert(insertIndex, music);
      
      // 如果当前没有正在播放的音乐，则直接添加到开头
      if (_currentTrackIndex < 0) {
        _currentTrackIndex = 0;
      }
    }
    
    await _savePlayList(); // 保存到持久化存储
  }

  @override
  Future<void> playNext() async {
    if (_playList.isEmpty) return;

    switch (_playMode) {
      case PlayMode.sequential:
        _currentTrackIndex = (_currentTrackIndex + 1) % _playList.length;
        break;
      case PlayMode.loop:
      // 单曲循环直接重新播放当前歌曲
        break;
      case PlayMode.shuffle:
        final random = Random();
        var newIndex = random.nextInt(_playList.length);
        // 确保不会重复播放同一首歌
        while (newIndex == _currentTrackIndex && _playList.length > 1) {
          newIndex = random.nextInt(_playList.length);
        }
        _currentTrackIndex = newIndex;
        break;
    }

    await _playCurrentTrack();
    // 更新媒体通知
    _audioHandler.customEvent.add({'type': 'next'});
    // 添加到播放历史记录
    if (currentMusic != null) {
      _addToPlayHistory(currentMusic!);
    }
  }

  @override
  Future<void> playPrevious() async {
    if (_playList.isEmpty) return;

    if (_audioPlayer.position > const Duration(seconds: 3)) {
      // 如果当前歌曲播放超过3秒，则重新播放当前歌曲
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    switch (_playMode) {
      case PlayMode.sequential:
        _currentTrackIndex =
            (_currentTrackIndex - 1 + _playList.length) % _playList.length;
        break;
      case PlayMode.loop:
      // 单曲循环直接重新播放当前歌曲
        break;
      case PlayMode.shuffle:
        final random = Random();
        var newIndex = random.nextInt(_playList.length);
        // 确保不会重复播放同一首歌
        while (newIndex == _currentTrackIndex && _playList.length > 1) {
          newIndex = random.nextInt(_playList.length);
        }
        _currentTrackIndex = newIndex;
        break;
    }

    await _playCurrentTrack();
    // 更新媒体通知
    _audioHandler.customEvent.add({'type': 'previous'});
    // 添加到播放历史记录
    if (currentMusic != null) {
      _addToPlayHistory(currentMusic!);
    }
  }

  @override
  Future<void> playAtIndex(int index) async {
    if (index >= 0 && index < _playList.length) {
      _currentTrackIndex = index;
      await _playCurrentTrack();
      // 添加到播放历史记录
      if (currentMusic != null) {
        _addToPlayHistory(currentMusic!);
      }
    }
  }

  @override
  int getCurrentIndex() {
    return _currentTrackIndex;
  }

  @override
  int getPlaylistLength() {
    return _playList.length;
  }

  @override
  double getProgressPercentage() {
    if (_audioPlayer.duration == null ||
        _audioPlayer.duration!.inMilliseconds == 0) {
      return 0.0;
    }
    return _audioPlayer.position.inMilliseconds /
        _audioPlayer.duration!.inMilliseconds;
  }

  @override
  Future<void> dispose() async {
    // 停止播放并释放音频资源
    await stop();

    // 取消所有订阅
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // 释放音频播放器
    await _audioPlayer.dispose();

    // 清除所有监听器
    _stateListeners.clear();
    _positionListeners.clear();

    // 清理媒体通知
    AudioService.stop();
  }

  void _notifyStateListeners(AudioState state) {
    for (final listener in _stateListeners) {
      listener(state);
    }
  }

  void _notifyPositionListeners(Duration position) {
    for (final listener in _positionListeners) {
      listener(position);
    }
  }

  Future<void> _getSavedPlayList() async {
    try {
      if (_prefs == null) return;
      final playlistJson = _prefs!.getString('playlist');
      if (playlistJson != null && playlistJson.isNotEmpty) {
        debugPrint('Playlist loaded: $playlistJson');
        final decoded = jsonDecode(playlistJson);
        if (decoded is List<dynamic>) {
          final playlist = decoded;
          final tempList = playlist.map((json) {
            try {
              return model.Music.fromJson(json);
            } catch (e) {
              debugPrint('Failed to parse music item: $e');
              return null;
            }
          }).where((music) => music != null).cast<model.Music>().toList();
          _playList.clear();
          _playList.addAll(tempList);
        }
      }
    } catch (e) {
      debugPrint('Failed to load playlist: $e');
      // 可以根据需要重新抛出或处理异常
    }
  }

  Future<void> _savePlayList() async {
    debugPrint('Saving playlist with $_playList.length items');

    final playlistJson = jsonEncode(
      _playList.map((music) => music.toJson()).toList(),
    );
    // 使用已初始化的SharedPreferences实例
    if (_prefs != null) {
      await _prefs!.setString('playlist', playlistJson);
    }
  }

  Future<void> _clearSavedPlayList() async {
    debugPrint('Clearing saved playlist');

    // 使用已初始化的SharedPreferences实例
    if (_prefs != null) {
      await _prefs!.remove('playlist');
    }
  }
  
  // 获取播放历史记录
  Future<void> _getPlayHistory() async {
    try {
      if (_prefs == null) return;
      final historyJson = _prefs!.getString('play_history');
      if (historyJson != null && historyJson.isNotEmpty) {
        debugPrint('Play history loaded: $historyJson');
        final decoded = jsonDecode(historyJson);
        if (decoded is List<dynamic>) {
          final history = decoded;
          final tempList = history.map((json) {
            try {
              return model.Music.fromJson(json);
            } catch (e) {
              debugPrint('Failed to parse music item in history: $e');
              return null;
            }
          }).where((music) => music != null).cast<model.Music>().toList();
          _playHistory.clear();
          _playHistory.addAll(tempList);
        }
      }
    } catch (e) {
      debugPrint('Failed to load play history: $e');
    }
  }
  
  // 保存播放历史记录
  Future<void> _savePlayHistory() async {
    debugPrint('Saving play history with $_playHistory.length items');

    final historyJson = jsonEncode(
      _playHistory.map((music) => music.toJson()).toList(),
    );
    // 使用已初始化的SharedPreferences实例
    if (_prefs != null) {
      await _prefs!.setString('play_history', historyJson);
    }
  }
  
  // 添加音乐到播放历史记录
  void _addToPlayHistory(model.Music music) {
    // 检查是否已存在于历史记录中
    final existingIndex = _playHistory.indexWhere((m) => 
      m.id == music.id && 
      (m.pages.isEmpty && music.pages.isEmpty ||
       m.pages.isNotEmpty && music.pages.isNotEmpty &&
       m.pages[0].cid == music.pages[0].cid));
    
    if (existingIndex != -1) {
      // 如果存在，将其移到顶部
      _playHistory.removeAt(existingIndex);
      _playHistory.insert(0, music);
    } else {
      // 如果不存在，插入到顶部
      _playHistory.insert(0, music);
      // 限制历史记录数量为50条
      if (_playHistory.length > 50) {
        _playHistory.removeRange(50, _playHistory.length);
      }
    }
    
    // 异步保存历史记录
    _savePlayHistory();
  }

  // 获取收藏列表
  Future<void> _getFavorites() async {
    try {
      if (_prefs == null) return;
      final favoritesJson = _prefs!.getString('favorites');
      if (favoritesJson != null && favoritesJson.isNotEmpty) {
        debugPrint('Favorites loaded: $favoritesJson');
        final decoded = jsonDecode(favoritesJson);
        if (decoded is List<dynamic>) {
          final favorites = decoded;
          final tempList = favorites.map((json) {
            try {
              return model.Music.fromJson(json);
            } catch (e) {
              debugPrint('Failed to parse music item in favorites: $e');
              return null;
            }
          }).where((music) => music != null).cast<model.Music>().toList();
          _favorites.clear();
          _favorites.addAll(tempList);
        }
      }
    } catch (e) {
      debugPrint('Failed to load favorites: $e');
    }
  }
  
  // 保存收藏列表
  Future<void> _saveFavorites() async {
    debugPrint('Saving favorites with $_favorites.length items');

    final favoritesJson = jsonEncode(
      _favorites.map((music) => music.toJson()).toList(),
    );
    // 使用已初始化的SharedPreferences实例
    if (_prefs != null) {
      await _prefs!.setString('favorites', favoritesJson);
    }
  }
  
  // 添加音乐到收藏列表
  Future<void> addToFavorites(model.Music music) async {
    // 检查是否已存在于收藏列表中
    final existingIndex = _favorites.indexWhere((m) => 
      m.id == music.id && 
      (m.pages.isEmpty && music.pages.isEmpty ||
       m.pages.isNotEmpty && music.pages.isNotEmpty &&
       m.pages[0].cid == music.pages[0].cid));
    
    if (existingIndex == -1) {
      // 如果不存在，添加到收藏列表
      _favorites.add(music.copyWith(isFavorite: true));
      // 异步保存收藏列表
      await _saveFavorites();
      
      // 更新播放列表中的音乐状态
      final playListIndex = _playList.indexWhere((m) => 
        m.id == music.id && 
        (m.pages.isEmpty && music.pages.isEmpty ||
         m.pages.isNotEmpty && music.pages.isNotEmpty &&
         m.pages[0].cid == music.pages[0].cid));
         
      if (playListIndex != -1) {
        _playList[playListIndex] = _playList[playListIndex].copyWith(isFavorite: true);
        await _savePlayList();
      }
      
      // 更新播放历史中的音乐状态
      final historyIndex = _playHistory.indexWhere((m) => 
        m.id == music.id && 
        (m.pages.isEmpty && music.pages.isEmpty ||
         m.pages.isNotEmpty && music.pages.isNotEmpty &&
         m.pages[0].cid == music.pages[0].cid));
         
      if (historyIndex != -1) {
        _playHistory[historyIndex] = _playHistory[historyIndex].copyWith(isFavorite: true);
        await _savePlayHistory();
      }
      
      _notifyStateListeners(_currentState);
    }
  }
  
  // 从收藏列表中移除音乐
  Future<void> removeFromFavorites(model.Music music) async {
    // 查找要移除的音乐
    final index = _favorites.indexWhere((m) => 
      m.id == music.id && 
      (m.pages.isEmpty && music.pages.isEmpty ||
       m.pages.isNotEmpty && music.pages.isNotEmpty &&
       m.pages[0].cid == music.pages[0].cid));
    
    if (index != -1) {
      // 如果存在，从收藏列表中移除
      _favorites.removeAt(index);
      // 异步保存收藏列表
      await _saveFavorites();
      
      // 更新播放列表中的音乐状态
      final playListIndex = _playList.indexWhere((m) => 
        m.id == music.id && 
        (m.pages.isEmpty && music.pages.isEmpty ||
         m.pages.isNotEmpty && music.pages.isNotEmpty &&
         m.pages[0].cid == music.pages[0].cid));
         
      if (playListIndex != -1) {
        _playList[playListIndex] = _playList[playListIndex].copyWith(isFavorite: false);
        await _savePlayList();
      }
      
      // 更新播放历史中的音乐状态
      final historyIndex = _playHistory.indexWhere((m) => 
        m.id == music.id && 
        (m.pages.isEmpty && music.pages.isEmpty ||
         m.pages.isNotEmpty && music.pages.isNotEmpty &&
         m.pages[0].cid == music.pages[0].cid));
         
      if (historyIndex != -1) {
        _playHistory[historyIndex] = _playHistory[historyIndex].copyWith(isFavorite: false);
        await _savePlayHistory();
      }
      
      _notifyStateListeners(_currentState);
    }
  }
  
  // 检查音乐是否已收藏
  bool isFavorite(model.Music music) {
    return _favorites.any((m) => 
      m.id == music.id && 
      (m.pages.isEmpty && music.pages.isEmpty ||
       m.pages.isNotEmpty && music.pages.isNotEmpty &&
       m.pages[0].cid == music.pages[0].cid));
  }

  /// 添加播放模式变化监听器
  void addPlayModeListener(Function(PlayMode) listener) {
    // TODO: 实现添加播放模式变化监听器的逻辑
  }

  /// 移除播放模式变化监听器
  void removePlayModeListener(Function(PlayMode) listener) {
    // TODO: 实现移除播放模式变化监听器的逻辑
  }

  @override
  Duration get currentPosition => _audioPlayer.position;

  Duration get currentDuration => _audioPlayer.duration ?? Duration.zero;

  final MediaItem _mediaItem = MediaItem(
    id: '',
    title: '未知标题',
    artist: '未知艺术家',
    album: '未知专辑',
  );

  late MediaItem _currentMediaItem;

  // 更新媒体通知信息
  void _updateMediaNotification(model.Music music) {
    // 确保在UI线程执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mediaItem = MediaItem(
        id: music.id,
        title: music.title,
        artist: music.artist,
        album: music.album,
        duration: music.duration ?? Duration.zero,
        artUri: Uri.parse(music.coverUrl),
      );

      _audioHandler.mediaItem.add(mediaItem);
      _audioHandler.playbackState.add(PlaybackState(
        controls: _getMediaControls(),
        playing: _audioPlayer.playing,
        updatePosition: _audioPlayer.position,
        bufferedPosition: _audioPlayer.bufferedPosition ?? Duration.zero,
        speed: _audioPlayer.speed,
        processingState: _convertProcessingState(
            _audioPlayer.playerState.processingState),
      ));
    });
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '获取中...';
    }
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayerManager playerManager;

  AudioPlayerHandler(this.playerManager) {
    // // 初始状态设为 null
    // mediaItem.add(null);
    // playbackState.add(PlaybackState(
    //   controls: [],
    //   processingState: AudioProcessingState.idle,
    //   playing: false,
    // ));
  }

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