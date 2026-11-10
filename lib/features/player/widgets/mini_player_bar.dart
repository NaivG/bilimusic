import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/widgets/crossfade_indicator.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/animations.dart';
import 'package:bilimusic/shared/widgets/music_cover.dart';

/// 竖屏悬浮迷你播放器。
///
/// Chrome 浮块：14 圆角 + hairline + shadow；保留左右滑切歌、上滑展开与
/// 拖拽回弹。封面 40，进度条用 accentBorder 填充。
class MiniPlayerBar extends ConsumerStatefulWidget {
  final VoidCallback onExpand;
  final VoidCallback onPlayList;

  const MiniPlayerBar({
    super.key,
    required this.onExpand,
    required this.onPlayList,
  });

  @override
  ConsumerState<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<MiniPlayerBar>
    with TickerProviderStateMixin {
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
    _slideController = AnimationController(
      vsync: this,
      duration: BmMotion.large,
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
    final commands = ref.read(playbackCommandsProvider.notifier);
    if (_pendingDirection == -1) {
      commands.playPrevious();
    } else if (_pendingDirection == 1) {
      commands.playNext();
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_isTransitioning) return;
    final commands = ref.read(playbackCommandsProvider.notifier);
    final ps = ref.read(playerStateProvider);
    if (ps is PlayerPlaying) {
      await commands.pause();
    } else if (ps is PlayerPaused || ps is PlayerCompleted) {
      await commands.resume();
    }
  }

  // Gesture handlers
  void _onDragStart(DragStartDetails details) {
    if (_isTransitioning) return;
    _dragX = 0;
    _dragY = 0;
    _isDragging = false;
    _isVerticalSwipe = false;

    // 无音乐时不启动水平拖动
    if (ref.read(playerCoordinatorProvider).currentMusic == null) {
      _isVerticalSwipe = true;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isTransitioning) return;

    if (!_isDragging) {
      if (details.delta.dy.abs() > 1 &&
          details.delta.dy.abs() > details.delta.dx.abs()) {
        _isVerticalSwipe = true;
      } else if (details.delta.dx.abs() > 1) {
        _isDragging = true;
      }
    }

    if (_isVerticalSwipe) {
      setState(() {
        _dragY += details.delta.dy;
      });
      return;
    }

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

    final simulation = SpringSimulation(BmMotion.pressSpring, _dragX, 0, 0);

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
    final currentPosition = ref.watch(positionProvider);
    final currentPlayerState = ref.watch(playerStateProvider);
    ref.watch(currentMusicProvider);
    final colors = context.bmColors;
    final type = context.bmType;
    final blurEffect = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );

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
      padding: EdgeInsets.zero,
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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Chrome 浮块：白底 + 模糊 + 26 胶囊；整条高度画进度填充。
                BmChromeSurface(
                  floating: true,
                  tone: BmChromeTone.raised,
                  radius: BmTokens.miniPlayerRadius,
                  blur: blurEffect,
                  child: SizedBox(
                    height: BmTokens.miniPlayerHeight,
                    child: Stack(
                      children: [
                        // 背景进度条层（订阅 position）
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildProgressFill(colors, currentPosition),
                          ),
                        ),
                        // 滑动方向图标层
                        if (ref.read(playerCoordinatorProvider).currentMusic !=
                            null) ...[
                          if (_dragX > 20)
                            Positioned(
                              left:
                                  -BmTokens.touchScreen -
                                  (_dragX * 0.2).clamp(0.0, BmTokens.s5),
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Transform.scale(
                                  scale: iconScale,
                                  child: Opacity(
                                    opacity: iconOpacity,
                                    child: Icon(
                                      Icons.skip_previous_rounded,
                                      color: colors.textPrimary,
                                      size: BmTokens.touchScreen,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_dragX < -20)
                            Positioned(
                              right:
                                  -BmTokens.touchScreen -
                                  (_dragX.abs() * 0.2).clamp(0.0, BmTokens.s5),
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Transform.scale(
                                  scale: iconScale,
                                  child: Opacity(
                                    opacity: iconOpacity,
                                    child: Icon(
                                      Icons.skip_next_rounded,
                                      color: colors.textPrimary,
                                      size: BmTokens.touchScreen,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                        // 内容层
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BmTokens.s1 + 2,
                          ),
                          child: Row(
                            children: [
                              // 专辑封面
                              GestureDetector(
                                onTap: widget.onExpand,
                                child: MusicCover(
                                  music: ref
                                      .read(playerCoordinatorProvider)
                                      .currentMusic,
                                  size: BmTokens.miniPlayerCover,
                                  radius: BmTokens.rPill,
                                ),
                              ),
                              const SizedBox(width: BmTokens.s3),
                              // 歌曲信息（点击标题/歌手也可进入详情页）
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.onExpand,
                                  child: _buildSongInfo(
                                    colors,
                                    type,
                                    currentPlayerState,
                                  ),
                                ),
                              ),
                              // 控制按钮
                              BmIconButton(
                                icon: currentPlayerState is PlayerPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                tooltip: currentPlayerState is PlayerPlaying
                                    ? '暂停'
                                    : '播放',
                                color: colors.accent,
                                iconSize: BmTokens.iconLarge,
                                hitSize: BmTokens.touchScreen,
                                onPressed: _togglePlay,
                              ),
                              BmIconButton(
                                icon: Icons.playlist_play_rounded,
                                tooltip: '播放列表',
                                iconSize: BmTokens.iconLarge,
                                hitSize: BmTokens.touchScreen,
                                onPressed: widget.onPlayList,
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
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(
    BmColors colors,
    BmTypographySet type,
    PlayerState playerState,
  ) {
    final music = ref.read(playerCoordinatorProvider).currentMusic;
    final fading = isCrossfading(playerState);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          music?.title ?? 'Not Playing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.label.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (music != null) ...[
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: BmMotion.large,
            transitionBuilder: switcherFadeTransition,
            child: fading
                ? const CrossfadeIndicator()
                : Text(
                    music.artist.displayName,
                    key: const ValueKey('artist'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressFill(BmColors colors, Duration position) {
    final music = ref.read(playerCoordinatorProvider).currentMusic;
    final duration = music?.duration ?? Duration.zero;
    final p = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: p),
      duration: BmMotion.progress,
      curve: BmMotion.linear,
      builder: (context, value, child) {
        return FractionallySizedBox(
          widthFactor: value,
          heightFactor: 1,
          child: ColoredBox(
            color: colors.accent.withValues(alpha: BmAlpha.miniFill),
          ),
        );
      },
    );
  }
}
