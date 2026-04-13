import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/utils/responsive.dart';

/// Apple Music 风格的专辑封面组件
/// 大圆角 + 双色阴影效果
class AppleMusicCover extends StatefulWidget {
  final String coverUrl;
  final Color? dominantColor;
  final VoidCallback? onTap;
  final double? customSize;

  const AppleMusicCover({
    super.key,
    required this.coverUrl,
    this.dominantColor,
    this.onTap,
    this.customSize,
  });

  @override
  State<AppleMusicCover> createState() => _AppleMusicCoverState();
}

class _AppleMusicCoverState extends State<AppleMusicCover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.customSize ?? LandscapeBreakpoints.getCoverSize(context);
    final borderRadius = size > 300 ? 20.0 : 16.0;
    final dominantColor = widget.dominantColor ?? Colors.pink;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              // 内层彩色阴影
              BoxShadow(
                color: dominantColor.withValues(alpha: 0.45),
                blurRadius: 50,
                spreadRadius: 8,
                offset: const Offset(0, 25),
              ),
              // 外层深色阴影
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 40,
                spreadRadius: 12,
                offset: const Offset(0, 30),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: _buildCoverImage(size),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(double size) {
    if (widget.coverUrl.isEmpty) {
      return Container(
        color: Colors.grey[800],
        child: Center(
          child: Icon(
            Icons.music_note,
            color: Colors.white.withValues(alpha: 0.5),
            size: size * 0.4,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.coverUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[800],
        child: Center(
          child: SizedBox(
            width: size * 0.15,
            height: size * 0.15,
            child: CircularProgressIndicator(
              color: Colors.white.withValues(alpha: 0.5),
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[800],
        child: Center(
          child: Icon(
            Icons.music_note,
            color: Colors.white.withValues(alpha: 0.5),
            size: size * 0.4,
          ),
        ),
      ),
    );
  }
}

/// 带入场动画的封面组件
class AnimatedAppleMusicCover extends StatefulWidget {
  final String coverUrl;
  final Color? dominantColor;
  final VoidCallback? onTap;

  const AnimatedAppleMusicCover({
    super.key,
    required this.coverUrl,
    this.dominantColor,
    this.onTap,
  });

  @override
  State<AnimatedAppleMusicCover> createState() => _AnimatedAppleMusicCoverState();
}

class _AnimatedAppleMusicCoverState extends State<AnimatedAppleMusicCover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  String? _previousUrl;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // 延迟入场动画
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(AnimatedAppleMusicCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _previousUrl = oldWidget.coverUrl;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        );
      },
      child: AppleMusicCover(
        coverUrl: widget.coverUrl,
        dominantColor: widget.dominantColor,
        onTap: widget.onTap,
      ),
    );
  }
}
