import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 详情页模糊背景 —— 主导色渐变 + 封面高斯模糊 + 底部压暗三层 Stack。
/// 竖屏 / 方屏详情页共用（两份逐字拷贝的收敛件）。
class DetailBlurBackground extends StatelessWidget {
  final Color? dominantColor;
  final String coverUrl;

  const DetailBlurBackground({
    super.key,
    required this.dominantColor,
    required this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                dominantColor?.withValues(alpha: 0.8) ?? Colors.black,
                dominantColor?.withValues(alpha: 0.6) ?? Colors.grey[900]!,
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        if (coverUrl.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.3),
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
            ),
          ),
        ),
      ],
    );
  }
}
