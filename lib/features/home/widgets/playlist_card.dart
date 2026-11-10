import 'package:flutter/material.dart';

import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// Theater 歌单卡：正方形封面 + 标题 + 副标题。
///
/// 宽度由父级给（竖屏货架写死、横屏网格由列宽给）；系统歌单在封面
/// 左下角带一枚迷你图标徽章。
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.width,
    this.subtitle,
  });

  final Playlist playlist;
  final VoidCallback? onTap;

  /// 卡片宽度；为 null 时由父级约束决定（网格）。
  final double? width;

  /// 覆盖副标题；默认「N 首」。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final icon = _badgeIcon(playlist.id);
    final cover = Stack(
      fit: StackFit.expand,
      children: [
        BmArtImage(url: playlist.safeCoverUrl),
        if (icon != null)
          Positioned(
            left: BmTokens.s1 + BmTokens.s1 / 2,
            bottom: BmTokens.s1 + BmTokens.s1 / 2,
            child: _CoverBadge(icon: icon),
          ),
      ],
    );

    return BmMediaCard(
      width: width,
      cover: cover,
      title: playlist.name,
      subtitle: subtitle ?? '${playlist.songCount} 首',
      titleLines: 2,
      onTap: onTap,
    );
  }

  static IconData? _badgeIcon(String playlistId) {
    switch (playlistId) {
      case 'favorites':
        return Icons.favorite_rounded;
      case 'history':
        return Icons.schedule_rounded;
      case 'recommended':
        return Icons.auto_awesome_rounded;
      default:
        return null;
    }
  }
}

/// 封面左下角的迷你徽章（设计稿 22 圆、黑 44%）。
class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      width: BmTokens.s6 - BmTokens.s1 / 2,
      height: BmTokens.s6 - BmTokens.s1 / 2,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.scrim),
      alignment: Alignment.center,
      child: Icon(icon, size: BmTokens.iconInline, color: colors.stageText),
    );
  }
}
