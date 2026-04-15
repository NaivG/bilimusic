import 'package:flutter/material.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/landscape/apple_slider.dart';

/// 横屏底部播放控制条组件
/// 包含进度条和播放控制按钮
class LandscapeControlsBar extends StatelessWidget {
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isTransitioning;
  final IconData playModeIcon;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayModeToggle;
  final VoidCallback? onPlaylist;
  final Function(Duration)? onSeek;

  const LandscapeControlsBar({
    super.key,
    required this.position,
    this.duration,
    required this.isPlaying,
    this.isTransitioning = false,
    required this.playModeIcon,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onPlayModeToggle,
    this.onPlaylist,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final barHeight = LandscapeBreakpoints.getControlsBarHeight(context);
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);

    return Container(
      height: barHeight,
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
              builder: (context, constraints) {
                // 根据可用高度动态分配空间
                final availableHeight = constraints.maxHeight;
                final sliderHeight = availableHeight * 0.4;
                final buttonRowHeight = availableHeight * 0.5;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 进度条
                    SizedBox(
                      height: sliderHeight,
                      child: AppleMusicSlider(
                        position: position,
                        duration: duration,
                        onSeek: onSeek,
                        isTransitioning: isTransitioning,
                      ),
                    ),
                    // 这里由于时间有一定空间，所以不用空出位置
                    // 控制按钮
                    SizedBox(
                      height: buttonRowHeight,
                      child: _buildControlButtons(context),
                    ),
                    SizedBox(height: 4),
                  ],
                );
              },
            ),
          ),
    );
  }

  Widget _buildControlButtons(BuildContext context) {
    final buttonSize = LandscapeBreakpoints.getMainPlayButtonSize(context);
    final smallButtonSize = 36.0;
    final iconSize = buttonSize * 0.5;
    final smallIconSize = 24.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 播放模式
        _ControlButton(
          icon: playModeIcon,
          size: smallButtonSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: onPlayModeToggle,
        ),
        const SizedBox(width: 24),
        // 上一曲
        _ControlButton(
          icon: Icons.skip_previous,
          size: smallButtonSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: onPrevious,
        ),
        const SizedBox(width: 20),
        // 播放/暂停
        _PlayPauseButton(
          isPlaying: isPlaying,
          size: buttonSize,
          iconSize: iconSize,
          onTap: onPlayPause,
        ),
        const SizedBox(width: 20),
        // 下一曲
        _ControlButton(
          icon: Icons.skip_next,
          size: smallButtonSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: onNext,
        ),
        const SizedBox(width: 24),
        // 播放列表
        _ControlButton(
          icon: Icons.queue_music,
          size: smallButtonSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: onPlaylist,
        ),
      ],
    );
  }
}

/// 控制按钮组件
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color iconColor;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.iconColor,
    this.onTap,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Icon(
            widget.icon,
            color: widget.iconColor,
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }
}

/// 播放/暂停按钮组件
class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.size,
    required this.iconSize,
    this.onTap,
  });

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFE0E0E0)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.35),
                blurRadius: 25,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                widget.isPlaying ? Icons.pause : Icons.play_arrow,
                key: ValueKey(widget.isPlaying),
                color: Colors.black87,
                size: widget.iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 带毛玻璃效果的播放控制条
class FrostedLandscapeControlsBar extends StatelessWidget {
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isTransitioning;
  final IconData playModeIcon;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayModeToggle;
  final VoidCallback? onPlaylist;
  final Function(Duration)? onSeek;

  const FrostedLandscapeControlsBar({
    super.key,
    required this.position,
    this.duration,
    required this.isPlaying,
    this.isTransitioning = false,
    required this.playModeIcon,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onPlayModeToggle,
    this.onPlaylist,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LandscapeControlsBar(
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      isTransitioning: isTransitioning,
      playModeIcon: playModeIcon,
      onPlayPause: onPlayPause,
      onPrevious: onPrevious,
      onNext: onNext,
      onPlayModeToggle: onPlayModeToggle,
      onPlaylist: onPlaylist,
      onSeek: onSeek,
    );
  }
}
