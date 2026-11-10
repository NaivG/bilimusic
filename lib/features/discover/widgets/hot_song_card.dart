import 'package:flutter/material.dart';

import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/related_video.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/surfaces/bm_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 热歌榜条目卡片：上半是榜单歌曲行头，下半是实际播放的相关视频。
class HotSongCard extends StatelessWidget {
  final HotSong song;
  final VoidCallback? onTap;
  final MenuProvider? contextMenuBuilder;

  const HotSongCard({
    super.key,
    required this.song,
    this.onTap,
    this.contextMenuBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = song.isPlayable;

    final card = LayoutBuilder(
      builder: (context, constraints) {
        // 四列网格里单卡更窄，收紧封面与尾部信息，避免标题被挤没。
        final compact = constraints.maxWidth < 300;
        return BmCard(
          child: BmPressable(
            onTap: enabled ? onTap : null,
            enabled: enabled,
            borderRadius: BmTokens.r14All,
            semanticLabel: '${song.title}，${song.subtitleText}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                BmTokens.s2,
                BmTokens.s2,
                BmTokens.s3,
                BmTokens.s2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSongRow(context, compact),
                  if (_hasVideoIdentity(song.relatedVideo)) ...[
                    const SizedBox(height: BmTokens.s2),
                    _buildVideoRow(context, song.relatedVideo!, compact),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    final menuBuilder = contextMenuBuilder;
    if (!enabled || menuBuilder == null) return card;
    return AppContextMenu(menuProvider: menuBuilder, child: card);
  }

  // ------------------------------------------------------------ 歌曲行头

  Widget _buildSongRow(BuildContext context, bool compact) {
    final colors = context.bmColors;
    final type = context.bmType;
    final song = this.song;
    final isNew = song.rankDelta == null;
    final coverSize = compact ? BmTokens.controlLg : BmTokens.row;

    return Row(
      children: [
        SizedBox(
          width: compact ? BmTokens.s6 : BmTokens.s8,
          child: _buildRank(context),
        ),
        ClipRRect(
          borderRadius: BmTokens.albumArtRadius,
          child: SizedBox(
            width: coverSize,
            height: coverSize,
            child: BmArtImage(
              url: song.coverUrl,
              cacheKey:
                  'hot-song-${song.musicId.isEmpty ? song.bvid : song.musicId}',
            ),
          ),
        ),
        const SizedBox(width: BmTokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isNew) ...[
                    const _NewBadge(),
                    const SizedBox(width: BmTokens.s1),
                  ],
                  Flexible(
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s1 / 2),
              Text(
                song.subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: BmTokens.s2),
        _buildSongTrailing(context, compact: compact),
      ],
    );
  }

  Widget _buildRank(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final song = this.song;
    final delta = song.rankDelta;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${song.rank}',
          textAlign: TextAlign.center,
          style: type.bodyStrong.copyWith(
            color: song.rank <= 3 ? colors.accent : colors.textTertiary,
          ),
        ),
        if (delta != null) ...[
          const SizedBox(height: BmTokens.s1 / 2),
          _buildRankDelta(context, delta),
        ],
      ],
    );
  }

  Widget _buildRankDelta(BuildContext context, int delta) {
    final colors = context.bmColors;
    final type = context.bmType;
    if (delta == 0) {
      return Text('—', style: type.micro.copyWith(color: colors.textTertiary));
    }

    final color = delta > 0 ? colors.success : colors.danger;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: BmTokens.iconInline,
            color: color,
          ),
          Text('${delta.abs()}', style: type.micro.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildSongTrailing(BuildContext context, {required bool compact}) {
    final colors = context.bmColors;
    final type = context.bmType;
    final song = this.song;
    final achievement = song.achievements
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' · ');
    final showAchievement = achievement.isNotEmpty && !compact;

    if (!showAchievement && song.heat <= 0) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 72 : 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAchievement)
            Text(
              achievement,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.micro.copyWith(color: colors.accentDeep),
            ),
          if (showAchievement && song.heat > 0)
            const SizedBox(height: BmTokens.s1 / 2),
          if (song.heat > 0)
            Text(
              _formatHeat(song.heat),
              style: type.micro.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 相关视频

  Widget _buildVideoRow(
    BuildContext context,
    RelatedVideo video,
    bool compact,
  ) {
    final colors = context.bmColors;
    final type = context.bmType;
    final width = compact ? 64.0 : 80.0;
    final height = compact ? 36.0 : 45.0;

    return Container(
      padding: const EdgeInsets.all(BmTokens.s1),
      decoration: BoxDecoration(
        color: colors.bgDeep,
        borderRadius: BmTokens.r9All,
      ),
      child: Row(
        children: [
          _buildVideoCover(context, video, width, height),
          const SizedBox(width: BmTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  video.title.trim().isEmpty ? '相关视频' : video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.label.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: BmTokens.s1 / 2),
                Text(
                  _videoSubtitle(video),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: BmTokens.s2),
          Icon(
            Icons.play_circle_outline_rounded,
            size: BmTokens.icon,
            color: colors.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCover(
    BuildContext context,
    RelatedVideo video,
    double width,
    double height,
  ) {
    final colors = context.bmColors;
    final type = context.bmType;
    final duration = song.durationSeconds;

    return ClipRRect(
      borderRadius: BmTokens.r4All,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BmArtImage(
              url: video.coverUrl,
              cacheKey: 'hot-video-${video.bvid}',
            ),
            if (duration > 0)
              Positioned(
                right: BmTokens.s1 / 2,
                bottom: BmTokens.s1 / 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.s1 / 2,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.scrim,
                    borderRadius: BmTokens.r4All,
                  ),
                  child: Text(
                    formatDuration(Duration(seconds: duration)),
                    style: type.micro.copyWith(color: colors.stageText),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 通用

  /// 相关视频身份是否至少有一项可展示（旧缓存可能只有 bvid）。
  bool _hasVideoIdentity(RelatedVideo? video) {
    if (video == null) return false;
    return video.title.trim().isNotEmpty ||
        video.uploaderName.trim().isNotEmpty ||
        video.playCount > 0 ||
        video.coverUrl.trim().isNotEmpty;
  }

  String _videoSubtitle(RelatedVideo video) {
    final parts = <String>[
      if (video.uploaderName.trim().isNotEmpty) video.uploaderName.trim(),
      if (video.playCount > 0) '${formatCount(video.playCount)}播放',
    ];
    return parts.isEmpty ? '相关视频' : parts.join(' · ');
  }

  static String _formatHeat(int heat) {
    if (heat >= 10000) return '${formatCount(heat)}热度';
    return '$heat 热度';
  }
}

/// 新上榜角标。
class _NewBadge extends StatelessWidget {
  const _NewBadge();

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
        color: colors.accentSoft,
        borderRadius: BmTokens.r4All,
      ),
      child: Text(
        '新',
        style: type.micro.copyWith(
          color: colors.accentDeep,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
