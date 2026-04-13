import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/landscape/apple_cover.dart';

/// 横屏左侧封面区域组件
/// 包含封面展示和功能按钮（收藏、分享）
class LandscapeAlbumSection extends StatelessWidget {
  final String coverUrl;
  final String title;
  final String artist;
  final String album;
  final Color? dominantColor;
  final bool isFavorite;
  final VoidCallback? onFavoritePressed;
  final VoidCallback? onSharePressed;
  final VoidCallback? onCoverTap;

  const LandscapeAlbumSection({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.artist,
    required this.album,
    this.dominantColor,
    this.isFavorite = false,
    this.onFavoritePressed,
    this.onSharePressed,
    this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);
    final coverSize = LandscapeBreakpoints.getCoverSize(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 封面
          AppleMusicCover(
            coverUrl: coverUrl,
            dominantColor: dominantColor,
            onTap: onCoverTap,
            customSize: coverSize,
          ),
          const SizedBox(height: 32),
          // 功能按钮组
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final buttonSize = 44.0;
    final iconSize = 24.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 收藏按钮
              _ActionButton(
                icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                iconColor: isFavorite ? (Colors.red[400] ?? Colors.red) : Colors.white,
                size: buttonSize,
                iconSize: iconSize,
                onTap: onFavoritePressed,
              ),
              const SizedBox(width: 8),
              // 分享按钮
              _ActionButton(
                icon: Icons.share_outlined,
                iconColor: Colors.white,
                size: buttonSize,
                iconSize: iconSize,
                onTap: onSharePressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 功能按钮组件
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.size,
    required this.iconSize,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
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
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
          ),
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

/// 带收藏动画的专辑区域组件
class AnimatedLandscapeAlbumSection extends StatefulWidget {
  final String coverUrl;
  final String title;
  final String artist;
  final String album;
  final Color? dominantColor;
  final bool isFavorite;
  final VoidCallback? onFavoritePressed;
  final VoidCallback? onSharePressed;
  final VoidCallback? onCoverTap;

  const AnimatedLandscapeAlbumSection({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.artist,
    required this.album,
    this.dominantColor,
    this.isFavorite = false,
    this.onFavoritePressed,
    this.onSharePressed,
    this.onCoverTap,
  });

  @override
  State<AnimatedLandscapeAlbumSection> createState() =>
      _AnimatedLandscapeAlbumSectionState();
}

class _AnimatedLandscapeAlbumSectionState
    extends State<AnimatedLandscapeAlbumSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _previousFavorite = false;

  @override
  void initState() {
    super.initState();
    _previousFavorite = widget.isFavorite;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    // 延迟启动动画
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: LandscapeAlbumSection(
          coverUrl: widget.coverUrl,
          title: widget.title,
          artist: widget.artist,
          album: widget.album,
          dominantColor: widget.dominantColor,
          isFavorite: widget.isFavorite,
          onFavoritePressed: widget.onFavoritePressed,
          onSharePressed: widget.onSharePressed,
          onCoverTap: widget.onCoverTap,
        ),
      ),
    );
  }
}
