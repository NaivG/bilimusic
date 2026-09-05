import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 横屏模式封面组件
/// 基于ParticleMusic的CoverArtWidget适配bilimusic的Music模型
class LandscapeCoverArt extends StatelessWidget {
  final double? size;
  final double borderRadius;
  final Music? song;
  final double elevation;
  final Color? color;
  final VoidCallback? onTap;

  const LandscapeCoverArt({
    super.key,
    this.size,
    this.borderRadius = 0,
    this.song,
    this.elevation = 0,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = Material(
      elevation: elevation,
      color: color ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: content(context),
    );

    if (onTap != null) {
      child = GestureDetector(onTap: onTap, child: child);
    }

    return child;
  }

  Widget content(BuildContext context) {
    final coverUrl = song?.coverUrl;

    if (coverUrl == null || coverUrl.isEmpty) {
      return musicNote();
    }

    return CachedNetworkImage(
      imageUrl: coverUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (context, url) => SizedBox(
        width: size,
        height: size,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, error, stackTrace) => musicNote(),
    );
  }

  Widget musicNote() {
    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.music_note,
        size: size != null ? size! * 0.4 : 24,
        color: Colors.grey,
      ),
    );
  }
}

