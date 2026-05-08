import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/theme/lucent_theme.dart';

/// Mini Player Bar
/// 应用Lucent主题下的迷你播放器
class MiniPlayerBar extends StatefulWidget {
  final VoidCallback onExpand;
  final VoidCallback onPlayList;

  const MiniPlayerBar({
    super.key,
    required this.onExpand,
    required this.onPlayList,
  });

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with TickerProviderStateMixin {
  AudioState? _audioState;
  Music? _currentMusic;
  Duration _position = Duration.zero;
  int _crossfadeCountdown = -1;

  // Gesture state
  double _dragX = 0;
  double _dragY = 0;
  bool _isDragging = false;
  bool _isTransitioning = false;
  bool _isVerticalSwipe = false;

  // Animation
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  double _outgoingOffset = 0;

  // Pending direction for transition
  int? _pendingDirection; // -1 = previous, 1 = next

  @override
  void initState() {
    super.initState();
    _audioState = sl.playerManager.currentState;
    _currentMusic = sl.playerManager.currentMusic;
    _crossfadeCountdown = sl.playerManager.crossfadeCountdown.value;

    sl.playerManager.addStateListener(_updateAudioState);
    sl.playerManager.addPositionListener(_updatePosition);
    sl.playerManager.addMusicListener(_updateMusic);
    sl.playerManager.addCountdownListener(_updateCountdown);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = _slideController.drive(Tween<double>(begin: 0, end: 0));
    _slideController.addStatusListener(_onSlideStatus);
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (_pendingDirection != null) {
        _applyPendingDirection();
      }
      _slideController.reset();
      _outgoingOffset = 0;
      _pendingDirection = null;
      setState(() {
        _isTransitioning = false;
        _dragX = 0;
      });
    }
  }

  void _applyPendingDirection() {
    if (_pendingDirection == -1) {
      sl.playerManager.playPrevious();
    } else if (_pendingDirection == 1) {
      sl.playerManager.playNext();
    }
  }

  void _updateAudioState(AudioState state) {
    if (mounted) {
      setState(() {
        _audioState = state;
      });
      debugPrint('_updateAudioState: $state');
    }
  }

  void _updatePosition(Duration position) {
    if (mounted) {
      setState(() {
        _position = position;
      });
    }
  }

  void _updateMusic(Music? music) {
    if (mounted && music != null) {
      setState(() {
        _currentMusic = music;
      });
    }
  }

  void _updateCountdown(int countdown) {
    if (mounted) {
      setState(() {
        _crossfadeCountdown = countdown;
      });
    }
  }

  @override
  void dispose() {
    sl.playerManager.removeStateListener(_updateAudioState);
    sl.playerManager.removePositionListener(_updatePosition);
    sl.playerManager.removeMusicListener(_updateMusic);
    sl.playerManager.removeCountdownListener(_updateCountdown);
    _slideController.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_isTransitioning) return;
    if (_audioState == AudioState.playing) {
      await sl.playerManager.pause();
    } else {
      await sl.playerManager.resume();
    }
  }

  double get _progress {
    final duration = _currentMusic?.duration;
    if (duration == null || duration.inMilliseconds == 0) return 0.0;
    return (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  // Gesture handlers
  void _onDragStart(DragStartDetails details) {
    if (_isTransitioning) return;
    _dragX = 0;
    _dragY = 0;
    _isDragging = false;
    _isVerticalSwipe = false;

    // 无音乐时不启动水平拖动
    if (_currentMusic == null) {
      _isVerticalSwipe = true;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isTransitioning) return;

    if (!_isDragging) {
      if (details.delta.dy.abs() > 1 &&
          details.delta.dy.abs() > details.delta.dx.abs()) {
        _isVerticalSwipe = true;
        return;
      }
      if (details.delta.dx.abs() > 1) {
        _isDragging = true;
      }
    }

    if (_isVerticalSwipe) return;

    if (_isDragging) {
      setState(() {
        _dragX += details.delta.dx;
        _dragY += details.delta.dy;
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isTransitioning) return;

    if (_isVerticalSwipe) {
      if (_dragY < -60) {
        widget.onExpand();
      }
      _dragX = 0;
      _dragY = 0;
      return;
    }

    if (!_isDragging) {
      _dragX = 0;
      return;
    }

    final dx = _dragX;

    if (dx > 60) {
      // Swipe right -> previous
      _triggerSlideTransition(-1);
    } else if (dx < -60) {
      // Swipe left -> next
      _triggerSlideTransition(1);
    } else {
      // Snap back
      _snapBack();
    }
  }

  void _triggerSlideTransition(int direction) {
    setState(() {
      _isTransitioning = true;
      _pendingDirection = direction;
      _outgoingOffset = _dragX;
    });

    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset = direction * screenWidth;

    _slideAnimation = _slideController.drive(
      Tween<double>(begin: _outgoingOffset, end: targetOffset),
    );

    _slideController.forward(from: 0);
  }

  void _snapBack() {
    _slideAnimation = _slideController.drive(
      Tween<double>(begin: _dragX, end: 0),
    );

    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1),
      _dragX,
      0,
      0,
    );

    _slideController.animateWith(simulation);
    _slideController.addListener(_onSnapBackUpdate);
  }

  void _onSnapBackUpdate() {
    setState(() {
      _dragX = _slideAnimation.value;
    });
    if (_slideController.isCompleted || _slideController.isDismissed) {
      _slideController.removeListener(_onSnapBackUpdate);
      if (_slideController.isCompleted) {
        setState(() {
          _dragX = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? LucentTokens.darkSurfaceOverlay
        : LucentTokens.lightSurfaceOverlay;
    final progressColor = isDark
        ? LucentTokens.darkSurfaceHover
        : LucentTokens.lightSurfaceHover;
    final textPrimary = isDark
        ? LucentTokens.darkTextPrimary
        : LucentTokens.lightTextPrimary;
    final textSecondary = isDark
        ? LucentTokens.darkTextSecondary
        : LucentTokens.lightTextSecondary;

    final blurEffect = sl.settingsManager.blurEffect;

    // Compute scale/opacity based on drag distance
    final absDragX = _dragX.abs();
    final scale = absDragX > 20
        ? (1 - (absDragX.abs() / 1000)).clamp(0.92, 1.0)
        : 1.0;

    // 计算滑动方向图标 scale 和 opacity
    final iconScale = absDragX > 20
        ? (0.5 + (absDragX / 200)).clamp(0.5, 1.2)
        : 0.5;
    final iconOpacity = absDragX > 20
        ? ((absDragX - 20) / 40).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: EdgeInsets.only(left: 12, right: 12),
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Transform.translate(
          offset: Offset(
            _slideController.isAnimating ? _slideAnimation.value : _dragX,
            0,
          ),
          child: Transform.scale(
            scale: scale,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 毛玻璃层
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        LucentTokens.radiusLg,
                      ),
                      child: BackdropFilter(
                        filter: blurEffect
                            ? ImageFilter.blur(
                                sigmaX: LucentTokens.overlayBlurSigma,
                                sigmaY: LucentTokens.overlayBlurSigma,
                              )
                            : ImageFilter.blur(),
                        child: Container(
                          height: 68,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(
                              LucentTokens.radiusLg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 背景进度条层
                    Positioned.fill(
                      child: ClipRRect(
                        // 圆角遮罩
                        borderRadius: BorderRadius.circular(
                          LucentTokens.radiusLg,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TweenAnimationBuilder<double>(
                            // 进度条动画
                            tween: Tween(
                              begin: 0,
                              end: _progress.clamp(0.0, 1.0),
                            ),
                            duration: LucentTokens.standardDuration,
                            curve: LucentTokens.standardEasing,
                            builder: (context, value, child) {
                              return Container(
                                width: constraints.maxWidth * value,
                                color: progressColor,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    // 滑动方向图标层
                    if (_currentMusic != null) ...[
                      // 上一首图标（向右滑时显示在左侧）
                      if (_dragX > 20)
                        Positioned(
                          left: -44 - (_dragX * 0.2).clamp(0.0, 20.0),
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Transform.scale(
                              scale: iconScale,
                              child: Opacity(
                                opacity: iconOpacity,
                                child: Icon(
                                  Icons.skip_previous_rounded,
                                  color: textPrimary,
                                  size: 44,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // 下一首图标（向左滑时显示在右侧）
                      if (_dragX < -20)
                        Positioned(
                          right: -44 - (_dragX.abs() * 0.2).clamp(0.0, 20.0),
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Transform.scale(
                              scale: iconScale,
                              child: Opacity(
                                opacity: iconOpacity,
                                child: Icon(
                                  Icons.skip_next_rounded,
                                  color: textPrimary,
                                  size: 44,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                    // 内容层
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          // 专辑封面
                          GestureDetector(
                            onTap: widget.onExpand,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                LucentTokens.radiusMd,
                              ),
                              child: _currentMusic != null
                                  ? CachedNetworkImage(
                                      imageUrl: _currentMusic!.safeCoverUrl,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          _buildCoverPlaceholder(),
                                      errorWidget: (context, url, error) =>
                                          _buildCoverPlaceholder(),
                                      cacheManager: imageCacheManager,
                                      cacheKey: _currentMusic!.id,
                                    )
                                  : _buildCoverPlaceholder(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 歌曲信息
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentMusic?.title ?? 'Not Playing',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (_currentMusic != null) ...[
                                  const SizedBox(height: 2),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: _crossfadeCountdown > 0
                                        ? _buildTransitionText()
                                        : Text(
                                            _currentMusic!.artist,
                                            key: const ValueKey('artist'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 控制按钮
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 播放/暂停按钮
                              GestureDetector(
                                onTap: _togglePlay,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    _audioState == AudioState.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: LucentTokens.accentPrimary,
                                    size: 28,
                                  ),
                                ),
                              ),
                              // 播放列表按钮
                              GestureDetector(
                                onTap: widget.onPlayList,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.playlist_play_rounded,
                                    color: textSecondary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textTertiary = isDark
        ? LucentTokens.darkTextTertiary
        : LucentTokens.lightTextTertiary;

    final surfaceHover = isDark
        ? LucentTokens.darkSurfaceHover
        : LucentTokens.lightSurfaceHover;

    return Container(
      width: 44,
      height: 44,
      color: surfaceHover,
      child: Icon(Icons.music_note_rounded, color: textTertiary, size: 24),
    );
  }

  Widget _buildTransitionText() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final transitionColor = isDark
        ? LucentTokens.accentPrimary.withValues(alpha: 0.8)
        : LucentTokens.accentPrimary.withValues(alpha: 0.8);

    return Row(
      key: const ValueKey('transition'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10, // 略小于字体高度，保持视觉平衡
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(transitionColor),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '过渡中',
            maxLines: 1,
            style: TextStyle(color: transitionColor, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
