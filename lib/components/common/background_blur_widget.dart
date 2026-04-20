import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:bilimusic/utils/color_infra.dart';

/// 背景模糊组件 - 从封面图片生成模糊背景效果
class BackgroundBlurWidget extends StatelessWidget {
  final String? coverUrl;

  const BackgroundBlurWidget({super.key, this.coverUrl});

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null || coverUrl!.isEmpty) {
      return Container(color: backgroundColor);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          coverUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Container(color: backgroundColor),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(color: backgroundBaseColor.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}
