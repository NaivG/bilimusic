import 'package:flutter/material.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
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
/// Apple Music 风格：无底色大图标，只保留 [ScaleOnHover] 悬停放大。
/// 默认不铺任何底色；底栏等需要桌面悬停反馈的场景可传 [hoverColor]。
class PlaybackControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color iconColor;
  final String? semanticLabel;

  /// 悬停 / 按压时的底色。为 null 时完全透明（纯 AM 无底色样式）。
  final Color? hoverColor;
  final VoidCallback? onTap;

  const PlaybackControlButton({
    super.key,
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.iconColor,
    this.semanticLabel,
    this.hoverColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overlay = hoverColor ?? Colors.transparent;
    return SizedBox(
      width: size,
      height: size,
      child: ScaleOnHover(
        hoverScale: 1.12,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(
            icon,
            size: iconSize,
            color: iconColor,
            semanticLabel: semanticLabel,
          ),
          splashRadius: size * 0.5,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          hoverColor: overlay,
          highlightColor: overlay,
          splashColor: overlay,
        ),
      ),
    );
  }
}

/// 主播放 / 暂停按钮 —— Apple Music 风格的无底色大图标。
/// [ScaleOnHover] 悬停轻微放大，[AnimatedSwitcher] 切换播放 / 暂停图标。
class PlaybackPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final double size;
  final double iconSize;
  final Color iconColor;

  /// 悬停 / 按压时的底色。为 null 时完全透明（纯 AM 无底色样式）。
  final Color? hoverColor;
  final VoidCallback? onTap;

  const PlaybackPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.size,
    required this.iconSize,
    this.iconColor = Colors.white,
    this.hoverColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overlay = hoverColor ?? Colors.transparent;
    return SizedBox(
      width: size,
      height: size,
      child: ScaleOnHover(
        hoverScale: 1.06,
        child: IconButton(
          onPressed: onTap,
          splashRadius: size * 0.5,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          hoverColor: overlay,
          highlightColor: overlay,
          splashColor: overlay,
          icon: AnimatedSwitcher(
            duration: BmMotion.medium,
            switchInCurve: BmMotion.standard,
            switchOutCurve: BmMotion.standard,
            transitionBuilder: switcherFadeTransition,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
