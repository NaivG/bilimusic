import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 竖版媒体卡：封面 + 标题 + 副标题。
///
/// 竖屏货架与横屏网格共用；宽度由外部给（货架写死，网格用
/// `LayoutBuilder` 分列）。封面单独一层，可挂 Hero 或入场动画。
class BmMediaCard extends StatelessWidget {
  const BmMediaCard({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.width,
    this.coverRadius = BmTokens.albumArtRadius,
    this.titleLines = 2,
    this.heroTag,
  });

  /// 封面（正方形，尺寸由 [width] 决定）。
  final Widget cover;

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 卡片宽度；为 null 时由父级约束决定（网格）。
  final double? width;

  final BorderRadius coverRadius;
  final int titleLines;

  /// 非空时给封面包一层 Hero。
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final subtitleText = subtitle;
    Widget art = ClipRRect(borderRadius: coverRadius, child: cover);
    final tag = heroTag;
    if (tag != null) art = Hero(tag: tag, child: art);

    return BmPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BmTokens.r12All,
      semanticLabel: subtitleText == null ? title : '$title，$subtitleText',
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(aspectRatio: 1, child: art),
            const SizedBox(height: BmTokens.s2),
            Text(
              title,
              maxLines: titleLines,
              overflow: TextOverflow.ellipsis,
              style: type.label.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitleText != null) ...[
              const SizedBox(height: 1),
              Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 网络封面图：bilibili 防盗链头 + 失败退化为占位块。
///
/// 尺寸由父级给（正方形），不内建圆角——需要时用 `ClipRRect` 包。
class BmArtImage extends StatelessWidget {
  const BmArtImage({super.key, required this.url, this.cacheKey});

  final String? url;

  /// 图片缓存键；不传时按 URL 哈希。
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) return _placeholder(colors);
    return CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: NetworkConfig.biliHeaders,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheManager: imageCacheManager,
      cacheKey: cacheKey,
      placeholder: (context, url) => _placeholder(colors),
      errorWidget: (context, url, error) => _placeholder(colors),
    );
  }

  Widget _placeholder(BmColors colors) {
    return ColoredBox(
      color: colors.bgDeep,
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          size: BmTokens.iconLarge,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
