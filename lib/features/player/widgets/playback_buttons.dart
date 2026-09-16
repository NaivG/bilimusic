import 'package:flutter/material.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/utils/animations.dart';

/// 半透明白底圆形图标按钮 —— 收藏 / 分享 / 任意迷你按钮。
/// 带按压缩放反馈。
class CircleIconButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.iconColor,
    this.backgroundColor,
    required this.size,
    required this.iconSize,
    this.onTap,
  });

  @override
  State<CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<CircleIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                widget.backgroundColor ?? Colors.white.withValues(alpha: 0.12),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              color: widget.iconColor,
              size: widget.iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放控制次按钮（mode / prev / next / queue）。
/// 与 LandscapeBottomControl 中央控制行的按钮同款：
/// [ScaleOnHover] 悬停放大 + [IconButton] 水波纹反馈，
/// hover 底色为歌曲卡片同款 ghost 风格轻浮雕。
class PlaybackControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color iconColor;
  final VoidCallback? onTap;

  const PlaybackControlButton({
    super.key,
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: size,
      height: size,
      child: ScaleOnHover(
        hoverScale: 1.12,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: iconSize, color: iconColor),
          splashRadius: size * 0.5,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          hoverColor: palette.surfaceHover.withValues(alpha: 0.35),
          highlightColor: palette.surfacePressed.withValues(alpha: 0.45),
          splashColor: palette.surfacePressed.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// 主播放 / 暂停按钮 —— 主题色圆形底 + [ScaleOnHover] 悬停放大
/// + [AnimatedSwitcher] 图标切换，与 LandscapeBottomControl 中央主按钮同款，
/// hover 底色为歌曲卡片同款 ghost 风格轻浮雕。
class PlaybackPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final double size;
  final double iconSize;
  final Color iconColor;

  /// 圆形底色，默认取 [Theme] 的 primary（与横屏底栏一致的强调色）。
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const PlaybackPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.size,
    required this.iconSize,
    this.backgroundColor,
    this.iconColor = Colors.white,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final accent = backgroundColor ?? Theme.of(context).colorScheme.primary;
    return ScaleOnHover(
      hoverScale: 1.05,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: IconButton(
          onPressed: onTap,
          splashRadius: size * 0.5,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          hoverColor: palette.surfaceHover.withValues(alpha: 0.35),
          highlightColor: palette.surfacePressed.withValues(alpha: 0.45),
          splashColor: palette.surfacePressed.withValues(alpha: 0.35),
          icon: AnimatedSwitcher(
            duration: AppTokens.standardDuration,
            switchInCurve: AppTokens.standardEasing,
            switchOutCurve: AppTokens.standardEasing,
            transitionBuilder: switcherFadeTransition,
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              key: ValueKey(isPlaying),
              size: iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// 全宽度轨道形状 —— 圆角矩形，active 段按 thumbCenter 截断。
/// 复用给音量条 / 任何无 thumb 的进度条。
class FullWidthTrackShape extends SliderTrackShape {
  const FullWidthTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final radius = Radius.circular(trackRect.height / 2);

    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()
        ..color = sliderTheme.inactiveTrackColor ?? Colors.white24
        ..style = PaintingStyle.fill,
    );

    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      Paint()
        ..color = sliderTheme.activeTrackColor ?? Colors.white
        ..style = PaintingStyle.fill,
    );
  }
}
