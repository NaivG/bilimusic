import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/components/player_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/utils/cache_manager.dart';
import 'package:bilimusic/utils/settings_manager.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

class MiniPlayerComponent extends StatefulWidget {
  final PlayerManager playerManager;
  final VoidCallback onExpand;
  final VoidCallback onPlayList;

  const MiniPlayerComponent({
    super.key,
    required this.playerManager,
    required this.onExpand,
    required this.onPlayList,
  });

  @override
  _MiniPlayerComponentState createState() => _MiniPlayerComponentState();
}

class _MiniPlayerComponentState extends State<MiniPlayerComponent> {
  late PlayerManager _playerManager;
  AudioState? _audioState;
  model.Music? _currentMusic;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayMode _playMode = PlayMode.sequential; // 添加播放模式状态
  final SettingsManager _settingsManager = SettingsManager();
  Color? _backgroundColor;

  @override
  void initState() {
    super.initState();
    _playerManager = widget.playerManager;
    _audioState = _playerManager.currentState;
    _currentMusic = _playerManager.currentMusic;
    _playMode = _playerManager.playMode;

    // 添加播放状态监听器
    _playerManager.addStateListener(_updateAudioState);
    // 添加播放位置监听器
    _playerManager.addPositionListener(_updatePosition);
    // 添加播放模式监听器
    _playerManager.addPlayModeListener(_updatePlayMode);
    
    // 初始化背景颜色
    _extractBackgroundColor();
  }

  bool _isTabletMode() {
    // 检查是否应该启用平板模式
    switch (_settingsManager.tabletMode) {
      case 'on':
        return true;
      case 'off':
        return false;
      case 'auto':
      default:
      // 自动模式：检查屏幕宽度是否大于600dp（平板阈值）
        return MediaQuery.of(context).size.shortestSide >= 600;
    }
  }

  bool _isPCMode() {
    // 检查是否应该启用PC模式
    return _settingsManager.pcMode;
  }

  /// 提取背景颜色
  void _extractBackgroundColor() async {
    final music = _playerManager.currentMusic;
    if (music == null || music.coverUrl.isEmpty) return;

    // 检查是否启用毛玻璃效果
    if (!_settingsManager.blurEffect) {
      setState(() {
        _backgroundColor = null;
      });
      return;
    }

    final color = await compute(_extractColorFromUrl, music.coverUrl);
    if (mounted) {
      setState(() {
        if (color == null) {
          _backgroundColor = null;
        } else {
          _backgroundColor = color.withOpacity(0.3);
        }
      });
    }
  }

  /// 在独立的函数中提取颜色，以便使用compute进行隔离计算
  static Future<Color?> _extractColorFromUrl(String imageUrl) async {
    return await ColorExtractor.extractColorFromUrl(imageUrl);
  }

  void _updatePlayMode(PlayMode playMode) {
    setState(() {
      _playMode = playMode;
    });
  }

  void _updateAudioState(AudioState state) {
    setState(() {
      _audioState = state;
      if (_playerManager.currentMusic != _currentMusic) {
        // 如果当前音乐已改变，则更新当前音乐
        _currentMusic = _playerManager.currentMusic;
        _extractBackgroundColor();
      }
    });
  }

  void _updatePosition(Duration position) {
    setState(() {
      _position = position;
    });
  }

  @override
  void dispose() {
    // 移除监听器
    _playerManager.removeStateListener(_updateAudioState);
    _playerManager.removePositionListener(_updatePosition);
    _playerManager.removePlayModeListener(_updatePlayMode);
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _togglePlay() async {
    if (_audioState == AudioState.playing) {
      await _playerManager.pause();
    } else {
      await _playerManager.resume();
    }
  }

  void _togglePlayMode() async {
    await _playerManager.togglePlayMode();
  }

  IconData _getPlayModeIcon(PlayMode playMode) {
    switch (playMode) {
      case PlayMode.sequential:
        return Icons.queue_music;
      case PlayMode.loop:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentMusic == null && _playerManager.currentMusic == null) {
      return Container(height: 0); // 如果没有当前音乐，不显示迷你播放器
    }

    final music = _currentMusic ?? _playerManager.currentMusic;
    final duration = music?.duration ?? Duration.zero;
    final position = _position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    bool isTablet = _isTabletMode();
    bool isPC = _isPCMode();
    bool blurEffect = _settingsManager.blurEffect;

    // 当音乐变化时重新提取背景颜色
    if (music != null && music.id != (_currentMusic?.id ?? '')) {
      _currentMusic = music;
      _extractBackgroundColor();
    }

    // PC模式下的特殊布局
    if (isPC) {
      return Container(
        height: 90,
        decoration: BoxDecoration(
          color: (blurEffect & (_backgroundColor != null))
            ?  _backgroundColor?.withOpacity(0.7)
            : Theme.of(context).primaryColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 5,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: Column(
          children: [
            // 进度条
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white30,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (music != null)
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/detail',
                                  arguments: widget.playerManager,
                                );
                              },
                              child: ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: music.safeCoverUrl,
                                  width: 50,
                                  height: 50,
                                  placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) {
                                    return const Icon(Icons.image_not_supported_rounded);
                                  },
                                  fit: BoxFit.cover,
                                  cacheManager: imageCacheManager,
                                  cacheKey: music.id,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    music.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '${music.artist} - ${music.album}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        ' / ',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.skip_previous,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: widget.playerManager.playPrevious,
                          ),
                          IconButton(
                            icon: Icon(
                              _audioState == AudioState.playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: _togglePlay,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.skip_next,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: widget.playerManager.playNext,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: Icon(
                              _getPlayModeIcon(_playMode),
                              color: Colors.white,
                            ),
                            onPressed: _togglePlayMode,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.playlist_play,
                              color: Colors.white,
                            ),
                            onPressed: widget.onPlayList,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.fullscreen,
                              color: Colors.white,
                            ),
                            onPressed: widget.onExpand,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: (blurEffect & (_backgroundColor != null))
          ?  _backgroundColor?.withOpacity(0.7)
          : Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(12), // 添加圆角
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        children: [
          // 进度条
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white30,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (music != null)
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                '/detail',
                                arguments: widget.playerManager,
                              );
                            },
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: music.safeCoverUrl,
                                width: 50,
                                height: 50,
                                placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) {
                                  return const Icon(Icons.image_not_supported_rounded);
                                },
                                fit: BoxFit.cover,
                                cacheManager: imageCacheManager,
                                cacheKey: music.id,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  music.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '${music.artist} - ${music.album}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      ' / ',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.playlist_play,
                            color: Colors.white,
                            size: 30,
                          ),
                          onPressed: widget.onPlayList,
                        ),
                        if (isTablet)
                          IconButton(
                            icon: Icon(
                              Icons.skip_previous,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: widget.playerManager.playPrevious,
                          ),
                        IconButton(
                          icon: Icon(
                            _audioState == AudioState.playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.white,
                            size: 40,
                          ),
                          onPressed: _togglePlay,
                        ),
                        if (isTablet)
                          IconButton(
                            icon: Icon(
                              Icons.skip_next,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: widget.playerManager.playNext,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}