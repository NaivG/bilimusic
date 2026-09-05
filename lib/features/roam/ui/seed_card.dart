import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/theme/app_palette.dart';
import 'package:bilimusic/theme/app_tokens.dart';

/// 单颗种子候选卡（步骤 B）。
///
/// Apple 风格：圆角 + 浅封面 + 标题 + 艺术家 + 选中态（高亮边框 + 微微提升）。
class SeedCard extends StatelessWidget {
  const SeedCard({
    super.key,
    required this.music,
    required this.selected,
    required this.onTap,
  });

  final Music music;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final radius = BorderRadius.circular(AppTokens.radiusMd);

    return AnimatedContainer(
      duration: AppTokens.microDuration,
      curve: AppTokens.standardEasing,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : palette.surfacePressed.withValues(alpha: 0.3),
        borderRadius: radius,
        border: Border.all(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: music.coverUrl.isEmpty
                        ? _placeholder(theme)
                        : CachedNetworkImage(
                            imageUrl: music.coverUrl,
                            cacheManager: imageCacheManager,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                _placeholder(theme, loading: true),
                            errorWidget: (_, _, _) => _placeholder(theme),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // 标题 + 艺术家
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        music.title.isEmpty ? '(无标题)' : music.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        music.artist.isEmpty ? '未知艺术家' : music.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 选中指示
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme, {bool loading = false}) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.music_note,
              color: theme.colorScheme.onSurfaceVariant,
              size: 24,
            ),
    );
  }
}
