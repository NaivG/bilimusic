import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 发现页的曲目行：可选排名列 + 封面 + 标题/副标题 + 自定义尾部。
class DiscoverMusicTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final String coverUrl;

  /// 图片缓存键（bvid / 歌曲 id），避免不同条目共用一个缓存槽。
  final String cacheKey;

  /// 榜单名次；为 null 时不占用排名列。
  final int? rank;

  /// 右侧附加信息（热度、时长等）。
  final Widget? trailing;

  /// 不可播放时置灰并禁用点击，同时不挂载右键/长按菜单。
  final bool enabled;
  final VoidCallback? onTap;

  /// 右键 / 长按菜单的构建器；为 null 或 [enabled] 为 false 时不接管。
  final MenuProvider? contextMenuBuilder;

  const DiscoverMusicTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.cacheKey,
    this.rank,
    this.trailing,
    this.enabled = true,
    this.onTap,
    this.contextMenuBuilder,
  });

  @override
  State<DiscoverMusicTile> createState() => _DiscoverMusicTileState();
}

class _DiscoverMusicTileState extends State<DiscoverMusicTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final accent = theme.colorScheme.primary;

    final row = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AppTokens.standardDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _isHovered ? palette.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: widget.enabled ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                children: [
                  if (widget.rank != null)
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${widget.rank}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: (widget.rank ?? 99) <= 3
                              ? accent
                              : theme.colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                        ),
                      ),
                    ),
                  _buildCover(theme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: widget.enabled
                                ? (_isHovered ? accent : null)
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.45,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 12),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final menuBuilder = widget.contextMenuBuilder;
    if (!widget.enabled || menuBuilder == null) return row;
    return ContextMenuWidget(menuProvider: menuBuilder, child: row);
  }

  Widget _buildCover(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: widget.coverUrl.isEmpty ? fallbackCoverUrl : widget.coverUrl,
        httpHeaders: NetworkConfig.biliHeaders,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheManager: imageCacheManager,
        cacheKey: widget.cacheKey,
        placeholder: (context, url) => Container(
          width: 44,
          height: 44,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 44,
          height: 44,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          child: Icon(
            Icons.music_note,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
