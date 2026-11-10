import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/surfaces/bm_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 发现页的曲目行：可选排名列 + 封面 + 标题/副标题 + 自定义尾部。
class DiscoverMusicTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    final row = BmPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      borderRadius: BmTokens.r10All,
      semanticLabel: subtitle.isEmpty ? title : '$title，$subtitle',
      child: SizedBox(
        height: BmTokens.trackRow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
          child: Row(
            children: [
              if (rank != null)
                SizedBox(
                  width: BmTokens.s8,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: type.bodyStrong.copyWith(
                      color: rank! <= 3 ? colors.accent : colors.textTertiary,
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BmTokens.albumArtRadius,
                child: SizedBox(
                  width: BmTokens.row,
                  height: BmTokens.row,
                  child: BmArtImage(url: coverUrl, cacheKey: cacheKey),
                ),
              ),
              const SizedBox(width: BmTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: BmTokens.s1 / 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: BmTokens.s3),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );

    final menuBuilder = contextMenuBuilder;
    if (!enabled || menuBuilder == null) return row;
    return AppContextMenu(menuProvider: menuBuilder, child: row);
  }
}

/// 发现页宽屏网格卡：方形封面 + 排名角标 + 标题/副标题/尾部。
class DiscoverMusicCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String coverUrl;
  final String cacheKey;
  final int? rank;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;
  final MenuProvider? contextMenuBuilder;

  const DiscoverMusicCard({
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
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    final card = BmCard(
      child: BmPressable(
        onTap: enabled ? onTap : null,
        enabled: enabled,
        borderRadius: BmTokens.r14All,
        semanticLabel: subtitle.isEmpty ? title : '$title，$subtitle',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BmArtImage(url: coverUrl, cacheKey: cacheKey),
                  if (rank != null)
                    Positioned(
                      left: BmTokens.s2,
                      top: BmTokens.s2,
                      child: _RankBadge(rank: rank!),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BmTokens.s3,
                BmTokens.s2,
                BmTokens.s3,
                BmTokens.s2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.label.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: BmTokens.s1 / 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: BmTokens.s1),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final menuBuilder = contextMenuBuilder;
    if (!enabled || menuBuilder == null) return card;
    return AppContextMenu(menuProvider: menuBuilder, child: card);
  }
}

/// 网格卡左上角的排名角标。
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s1,
        vertical: BmTokens.s1 / 2,
      ),
      decoration: BoxDecoration(
        color: colors.scrim,
        borderRadius: BmTokens.r4All,
      ),
      child: Text(
        '$rank',
        style: type.micro.copyWith(
          color: colors.stageText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
