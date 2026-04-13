import 'dart:ui';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 横屏详情页动态渐变背景组件
/// 基于封面颜色提取生成渐变效果
class LandscapeBackground extends StatelessWidget {
  final String coverUrl;
  final Color? dominantColor;
  final Widget child;

  const LandscapeBackground({
    super.key,
    required this.coverUrl,
    this.dominantColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 主背景渐变
        _buildGradientBackground(),
        // 封面图片模糊背景
        if (coverUrl.isNotEmpty) _buildBlurredCover(),
        // 底部暗角
        _buildBottomVignette(),
        // 内容
        child,
      ],
    );
  }

  /// 构建渐变背景
  Widget _buildGradientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dominantColor?.withValues(alpha: 0.85) ?? Colors.black,
            dominantColor?.withValues(alpha: 0.65) ?? Colors.grey[900]!,
            Colors.black,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
    );
  }

  /// 构建封面图片模糊背景
  Widget _buildBlurredCover() {
    return Positioned.fill(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
        child: CachedNetworkImage(
          imageUrl: coverUrl,
          fit: BoxFit.cover,
          color: Colors.black.withValues(alpha: 0.4),
          colorBlendMode: BlendMode.darken,
        ),
      ),
    );
  }

  /// 构建底部暗角渐变
  Widget _buildBottomVignette() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 200,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          ),
        ),
      ),
    );
  }
}

/// 带颜色动画的横屏背景组件
class AnimatedLandscapeBackground extends StatefulWidget {
  final String coverUrl;
  final Color? previousColor;
  final Color? newColor;
  final Widget child;

  const AnimatedLandscapeBackground({
    super.key,
    required this.coverUrl,
    this.previousColor,
    this.newColor,
    required this.child,
  });

  @override
  State<AnimatedLandscapeBackground> createState() =>
      _AnimatedLandscapeBackgroundState();
}

class _AnimatedLandscapeBackgroundState
    extends State<AnimatedLandscapeBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _setupAnimations();
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedLandscapeBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.newColor != widget.newColor && widget.newColor != null) {
      _setupAnimations();
      _controller.forward(from: 0);
    }
  }

  void _setupAnimations() {
    _colorAnimation = ColorTween(
      begin: widget.previousColor ?? widget.newColor,
      end: widget.newColor,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
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
        return Stack(
          fit: StackFit.expand,
          children: [
            // 主背景渐变
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (_colorAnimation.value ?? Colors.black).withValues(alpha: 0.85),
                    (_colorAnimation.value ?? Colors.black).withValues(alpha: 0.65),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            // 封面图片模糊背景
            if (widget.coverUrl.isNotEmpty)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                  child: Opacity(
                    opacity: _opacityAnimation.value,
                    child: CachedNetworkImage(
                      imageUrl: widget.coverUrl,
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.4),
                      colorBlendMode: BlendMode.darken,
                      cacheManager: imageCacheManager,
                    ),
                  ),
                ),
              ),
            // 底部暗角
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                  ),
                ),
              ),
            ),
            // 内容
            widget.child,
          ],
        );
      },
    );
  }
}
