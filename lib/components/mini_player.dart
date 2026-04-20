import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:flutter/foundation.dart';

/// 迷你播放器组件
class MiniPlayerComponent extends StatefulWidget {
  final VoidCallback onExpand;
  final VoidCallback onPlayList;

  const MiniPlayerComponent({
    super.key,
    required this.onExpand,
    required this.onPlayList,
  });

  @override
  _MiniPlayerComponentState createState() => _MiniPlayerComponentState();
}

class _MiniPlayerComponentState extends State<MiniPlayerComponent> {
  AudioState? _audioState;
  model.Music? _currentMusic;
  Duration _position = Duration.zero;

  /// 播放模式
  PlayMode _playMode = PlayMode.sequential;
  Color? _backgroundColor;

  /// crossfade倒计时（秒）
  int _crossfadeCountdown = -1;

  /// 收起状态
  bool _isCollapsed = false;

  /// 是否正在拖动
  bool _isDragging = false;

  /// 拖动开始位置
  double _dragStartY = 0;

  /// 当前拖动偏移
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _audioState = sl.playerManager.currentState;
    _currentMusic = sl.playerManager.currentMusic;
    _playMode = sl.playerManager.playMode;

    // 添加播放状态监听器
    sl.playerManager.addStateListener(_updateAudioState);
    // 添加播放位置监听器
    sl.playerManager.addPositionListener(_updatePosition);
    // 添加播放模式监听器
    sl.playerManager.addPlayModeListener(_updatePlayMode);
    // 添加crossfade倒计时监听器
    sl.playerManager.addCountdownListener(_updateCrossfadeCountdown);

    // 初始化背景颜色
    _extractBackgroundColor();
  }

  /// 检查是否应该启用平板模式
  bool _isTabletMode() {
    switch (sl.settingsManager.tabletMode) {
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

  /// 检查是否应该启用PC模式
  bool _isPCMode() {
    return sl.settingsManager.pcMode;
  }

  /// 提取背景颜色
  void _extractBackgroundColor() async {
    final music = sl.playerManager.currentMusic;
    if (music == null || music.coverUrl.isEmpty) return;

    // 检查是否启用毛玻璃效果
    if (!sl.settingsManager.blurEffect) {
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
          _backgroundColor = color.withValues(alpha: 0.3);
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
      // 检查音乐是否改变（可能在状态未变化时音乐已切换）
      if (sl.playerManager.currentMusic != null &&
          sl.playerManager.currentMusic?.id != _currentMusic?.id) {
        _currentMusic = sl.playerManager.currentMusic;
        _extractBackgroundColor();
      }
    });
  }

  void _updatePosition(Duration position) {
    setState(() {
      _position = position;
    });
  }

  void _updateCrossfadeCountdown(int countdown) {
    setState(() {
      _crossfadeCountdown = countdown;
    });
  }

  @override
  void dispose() {
    // 移除监听器
    sl.playerManager.removeStateListener(_updateAudioState);
    sl.playerManager.removePositionListener(_updatePosition);
    sl.playerManager.removePlayModeListener(_updatePlayMode);
    sl.playerManager.removeCountdownListener(_updateCrossfadeCountdown);
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
      await sl.playerManager.pause();
    } else {
      await sl.playerManager.resume();
    }
  }

  void _togglePlayMode() async {
    await sl.playerManager.togglePlayMode();
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

  /// 切换收起状态
  void _toggleCollapsed() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  /// 处理垂直拖动开始
  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragStartY = details.globalPosition.dy;
      _dragOffset = 0;
    });
  }

  /// 处理垂直拖动更新
  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = details.globalPosition.dy - _dragStartY;
    });
  }

  /// 处理垂直拖动结束
  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;

      // 根据拖动距离决定是否切换状态
      if (_dragOffset.abs() > 20) {
        if (_dragOffset > 0) {
          // 向下拖动，收起播放器
          _isCollapsed = true;
        } else {
          // 向上拖动，展开播放器
          _isCollapsed = false;
        }
      }

      _dragOffset = 0;
    });
  }

  /// 构建带动画的图标按钮
  Widget _buildAnimatedIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 24,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 150),
          tween: Tween<double>(begin: 1.0, end: 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                width: size + 12,
                height: size + 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
                child: Icon(icon, color: Colors.white, size: size),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建播放/暂停按钮，带有缩放动画和状态切换动画
  Widget _buildPlayPauseButton() {
    return GestureDetector(
      onTap: _togglePlay,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Container(
            key: ValueKey(_audioState == AudioState.playing),
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(
              _audioState == AudioState.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建收起状态的播放器
  Widget _buildCollapsedPlayer({
    required Color baseColor,
    required double progress,
    required double capsuleRadius,
    required bool isPC,
  }) {
    final double collapsedHeight = 20.0;

    return GestureDetector(
      onTap: _toggleCollapsed,
      onVerticalDragStart: _handleDragStart,
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: collapsedHeight,
        margin: EdgeInsets.symmetric(horizontal: isPC ? 16 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(capsuleRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              spreadRadius: 1,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 收起状态下的进度条
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  tween: Tween<double>(begin: 0, end: progress),
                  builder: (context, value, child) {
                    return LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(1),
                    );
                  },
                ),
              ),
            ),
            // 播放/暂停按钮
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 30,
                height: 30,
                margin: EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: Icon(
                  _audioState == AudioState.playing
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentMusic == null && sl.playerManager.currentMusic == null) {
      // 如果没有当前音乐，不显示迷你播放器
      return Container(height: 0);
    }

    final music = _currentMusic ?? sl.playerManager.currentMusic;
    final duration = music?.duration ?? Duration.zero;
    final position = _position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    bool isTablet = _isTabletMode();
    bool isPC = _isPCMode();
    bool blurEffect = sl.settingsManager.blurEffect;

    // 当音乐变化时重新提取背景颜色并更新_currentMusic
    if (music != null &&
        sl.playerManager.currentMusic != null &&
        music.id != sl.playerManager.currentMusic!.id) {
      setState(() {
        _currentMusic = sl.playerManager.currentMusic;
      });
      _extractBackgroundColor();
    }

    // 胶囊形播放器的高度
    final double playerHeight = isPC ? 75 : 70;
    // 胶囊圆角半径
    final double capsuleRadius = playerHeight / 2;

    // 基础背景颜色
    Color baseColor = Theme.of(context).primaryColor;
    if (blurEffect && _backgroundColor != null) {
      baseColor = _backgroundColor!.withValues(alpha: 0.7);
    }

    // PC模式下的特殊布局
    if (isPC) {
      return AnimatedContainer(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: playerHeight,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(capsuleRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              spreadRadius: 1,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (music != null)
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    // 专辑封面 - 添加动画效果
                    GestureDetector(
                      onTap: widget.onExpand,
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: music.safeCoverUrl,
                              placeholder: (context, url) => Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) {
                                return Container(
                                  color: Colors.white24,
                                  child: Icon(
                                    Icons.music_note,
                                    color: Colors.white70,
                                    size: 24,
                                  ),
                                );
                              },
                              fit: BoxFit.cover,
                              cacheManager: imageCacheManager,
                              cacheKey: music.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 歌曲标题 - 添加淡入淡出动画
                          AnimatedSwitcher(
                            duration: Duration(milliseconds: 300),
                            child: Text(
                              music.title,
                              key: ValueKey(music.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(height: 2),
                          // 艺术家和专辑信息
                          AnimatedSwitcher(
                            duration: Duration(milliseconds: 300),
                            child: Text(
                              '${music.artist} • ${music.album}',
                              key: ValueKey('${music.id}_artist'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          SizedBox(height: 2),
                          // 时间信息
                          Row(
                            children: [
                              // 如果正在倒计时，显示切换倒计时
                              if (_crossfadeCountdown > 0)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '过渡中 ${_crossfadeCountdown}s',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else ...[
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
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // 进度条 - 放在播放器底部
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 控制按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 播放模式按钮
                      _buildAnimatedIconButton(
                        icon: _getPlayModeIcon(_playMode),
                        onPressed: _togglePlayMode,
                        size: 22,
                      ),
                      // 上一曲按钮
                      _buildAnimatedIconButton(
                        icon: Icons.skip_previous,
                        onPressed: sl.playerManager.playPrevious,
                        size: 26,
                      ),
                      // 播放/暂停按钮 - 添加缩放动画
                      _buildPlayPauseButton(),
                      // 下一曲按钮
                      _buildAnimatedIconButton(
                        icon: Icons.skip_next,
                        onPressed: sl.playerManager.playNext,
                        size: 26,
                      ),
                      // 播放列表按钮
                      _buildAnimatedIconButton(
                        icon: Icons.playlist_play,
                        onPressed: widget.onPlayList,
                        size: 22,
                      ),
                    ],
                  ),
                  // 进度条
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      tween: Tween<double>(begin: 0, end: progress),
                      builder: (context, value, child) {
                        return LinearProgressIndicator(
                          value: value,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          minHeight: 2,
                          borderRadius: BorderRadius.circular(1),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // 扩展按钮
            Expanded(
              flex: 1,
              child: Center(
                child: _buildAnimatedIconButton(
                  icon: Icons.fullscreen,
                  onPressed: widget.onExpand,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 如果处于收起状态，显示收起布局
    if (_isCollapsed) {
      return _buildCollapsedPlayer(
        baseColor: baseColor,
        progress: progress,
        capsuleRadius: capsuleRadius,
        isPC: isPC,
      );
    }

    // 移动端/平板端布局（展开状态）
    return GestureDetector(
      onTap: _toggleCollapsed,
      onVerticalDragStart: _handleDragStart,
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: playerHeight,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(capsuleRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              spreadRadius: 1,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (music != null)
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    // 专辑封面
                    GestureDetector(
                      onTap: widget.onExpand,
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: music.safeCoverUrl,
                              placeholder: (context, url) => Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) {
                                return Container(
                                  color: Colors.white24,
                                  child: Icon(
                                    Icons.music_note,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                );
                              },
                              fit: BoxFit.cover,
                              cacheManager: imageCacheManager,
                              cacheKey: music.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 歌曲标题
                          AnimatedSwitcher(
                            duration: Duration(milliseconds: 300),
                            child: Text(
                              music.title,
                              key: ValueKey(music.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(height: 2),
                          // 艺术家信息
                          AnimatedSwitcher(
                            duration: Duration(milliseconds: 300),
                            child: _crossfadeCountdown > 0
                                ? Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.8,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '过渡中 ${_crossfadeCountdown}s',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : Text(
                                    music.artist,
                                    key: ValueKey('${music.id}_artist'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // 控制按钮区域
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 播放列表按钮
                  _buildAnimatedIconButton(
                    icon: Icons.playlist_play,
                    onPressed: widget.onPlayList,
                    size: 22,
                  ),
                  // 平板模式下显示上一曲/下一曲按钮
                  if (isTablet) ...[
                    _buildAnimatedIconButton(
                      icon: Icons.skip_previous,
                      onPressed: sl.playerManager.playPrevious,
                      size: 24,
                    ),
                  ],
                  // 播放/暂停按钮
                  _buildPlayPauseButton(),
                  // 平板模式下显示下一曲按钮
                  if (isTablet) ...[
                    _buildAnimatedIconButton(
                      icon: Icons.skip_next,
                      onPressed: sl.playerManager.playNext,
                      size: 24,
                    ),
                  ],
                  // 扩展按钮
                  _buildAnimatedIconButton(
                    icon: Icons.fullscreen,
                    onPressed: widget.onExpand,
                    size: 22,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
