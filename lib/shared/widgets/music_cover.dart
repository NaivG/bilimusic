import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';

/// 统一的音乐封面：bilibili 防盗链头 + 图片缓存管理器 + 以 `music.id` 为缓存键，
/// 加载占位与错误态统一为 music_note 占位块。
///
/// [music] 为空（无播放曲目）或 [radius] 为 null（外层自带裁剪）时的行为见构造参数。
class MusicCover extends StatelessWidget {
  final Music? music;
  final double size;

  /// 非空时内部按此圆角裁剪；外层已包 ClipRRect 则传 null 避免双重裁剪。
  final double? radius;

  const MusicCover({
    super.key,
    required this.music,
    required this.size,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final m = music;
    Widget child = m == null
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: m.safeCoverUrl,
            httpHeaders: NetworkConfig.biliHeaders,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (context, url) => _placeholder(context),
            errorWidget: (context, url, error) => _placeholder(context),
            cacheManager: imageCacheManager,
            cacheKey: m.id,
          );
    final r = radius;
    if (r != null) {
      child = ClipRRect(borderRadius: BorderRadius.circular(r), child: child);
    }
    return child;
  }

  Widget _placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      color: context.appPalette.surfaceHover,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onSurfaceVariant,
        size: size * 0.55,
      ),
    );
  }
}
