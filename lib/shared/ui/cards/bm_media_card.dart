import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_image.dart';
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
/// 默认按正方形裁切；[aspectRatio] 可指定 16:9 等横图。解码尺寸由父级给的
/// 宽度自动分桶，不内建圆角——需要时用 `ClipRRect` 包。
class BmArtImage extends StatelessWidget {
  const BmArtImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.aspectRatio = 1.0,
  });

  final String? url;

  /// 图片缓存键；不传时按 URL 哈希。内部会追加尺寸/比例，避免不同桶共用缓存。
  final String? cacheKey;

  /// 源图宽高比。默认正方形；首页 hero / 相关视频卡传 16 / 9。
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) return _placeholder(colors);
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = _targetWidth(context, constraints);
        final ratio = aspectRatio > 0 ? aspectRatio : 1.0;
        final targetHeight = (target / ratio).round().clamp(1, 100000).toInt();
        final resizedUrl = biliImageUrl(
          imageUrl,
          width: target,
          height: targetHeight,
        );
        return CachedNetworkImage(
          imageUrl: resizedUrl,
          httpHeaders: NetworkConfig.biliHeaders,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: target,
          cacheManager: imageCacheManager,
          // 同一曲目在不同尺寸 / 比例桶里是不同文件；缓存键必须带上尺寸。
          cacheKey: cacheKey == null
              ? null
              : '${cacheKey}_${target}x$targetHeight',
          placeholder: (context, url) => _placeholder(colors),
          errorWidget: (context, url, error) => _placeholder(colors),
        );
      },
    );
  }

  /// 按物理像素选一个尺寸桶，避免窗口每变 1px 就多解一份图。
  int _targetWidth(BuildContext context, BoxConstraints constraints) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logicalWidth = constraints.hasBoundedWidth && constraints.maxWidth > 0
        ? constraints.maxWidth
        : 352.0;
    final pixels = (logicalWidth * dpr).ceil();
    const steps = <int>[96, 176, 352, 768, 1600];
    for (final step in steps) {
      if (pixels <= step) return step;
    }
    return steps.last;
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
