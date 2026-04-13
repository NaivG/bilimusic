import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/music.dart' as model;

class CoverDisplayWidget extends StatelessWidget {
  final model.Music music;
  final double size;
  final bool showShadow;

  const CoverDisplayWidget({
    super.key,
    required this.music,
    this.size = 200,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: size,
      height: size,
      decoration: showShadow
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            )
          : null,
      child: Stack(
        children: [
          // 外圈装饰
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Theme.of(context).primaryColor.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.1, 0.8],
              ),
            ),
          ),
          
          // 封面图片容器
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: Container(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: music.coverUrl,
                    placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Icon(
                        Icons.music_note,
                        size: size * 0.3,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    fit: BoxFit.cover,
                    width: size - 16,
                    height: size - 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}