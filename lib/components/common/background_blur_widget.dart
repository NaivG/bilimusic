import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:bilimusic/theme/lucent_theme.dart';

/// 背景模糊组件 - 从封面图片生成模糊背景效果
class BackgroundBlurWidget extends StatelessWidget {
  final String? coverUrl;

  const BackgroundBlurWidget({super.key, this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final backgroundColor = LucentTokens.surfaceBase(brightness);

    if (coverUrl == null || coverUrl!.isEmpty) {
      return TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 250),
        tween: ColorTween(end: backgroundColor),
        builder: (context, color, child) => Container(color: color),
      );
    }

    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 250),
      tween: ColorTween(end: backgroundColor),
      builder: (context, color, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: color),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: LucentTokens.heavyGlassBlurSigma,
                sigmaY: LucentTokens.heavyGlassBlurSigma,
              ),
              child: Container(color: color?.withValues(alpha: 0.6)),
            ),
          ],
        );
      },
    );
  }
}
