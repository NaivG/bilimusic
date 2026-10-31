import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/related_video.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 热歌榜条目卡片：上半是榜单歌曲行头，下半是实际播放的相关视频。
class HotSongCard extends StatefulWidget {
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
  State<HotSongCard> createState() => _HotSongCardState();
}

class _HotSongCardState extends State<HotSongCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final enabled = widget.song.isPlayable;

    final card = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AppTokens.standardDuration,
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _isHovered
              ? palette.surfaceHover
              : palette.panelSurface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSongRow(context, enabled),
                  if (_hasVideoIdentity(widget.song.relatedVideo)) ...[
                    const SizedBox(height: 8),
                    _buildVideoRow(context, widget.song.relatedVideo!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final menuBuilder = widget.contextMenuBuilder;
    if (!enabled || menuBuilder == null) return card;
    return ContextMenuWidget(menuProvider: menuBuilder, child: card);
  }

  // ------------------------------------------------------------ 歌曲行头

  Widget _buildSongRow(BuildContext context, bool enabled) {
    final theme = Theme.of(context);
    final song = widget.song;
    final isNew = song.rankDelta == null;

    return Row(
      children: [
        SizedBox(width: 34, child: _buildRank(context)),
        _buildCover(
          context,
          song.coverUrl,
          cacheKey:
              'hot-song-${song.musicId.isEmpty ? song.bvid : song.musicId}',
          width: 44,
          height: 44,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isNew) ...[
                    _NewBadge(color: theme.colorScheme.primary),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: enabled
                            ? (_isHovered ? theme.colorScheme.primary : null)
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.45,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                song.subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildSongTrailing(context),
      ],
    );
  }

  Widget _buildRank(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;
    final delta = song.rankDelta;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${song.rank}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: song.rank <= 3
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
        if (delta != null) ...[
          const SizedBox(height: 1),
          _buildRankDelta(context, delta),
        ],
      ],
    );
  }

  Widget _buildRankDelta(BuildContext context, int delta) {
    final theme = Theme.of(context);
    if (delta == 0) {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 9,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );
    }

    final color = delta > 0 ? Colors.green : Colors.redAccent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 12,
          color: color,
        ),
        Text('${delta.abs()}', style: TextStyle(fontSize: 9, color: color)),
      ],
    );
  }

  Widget _buildSongTrailing(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;
    final achievement = song.achievements
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (achievement.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              achievement,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
          ),
        if (achievement.isNotEmpty) const SizedBox(height: 2),
        if (song.heat > 0)
          Text(
            _formatHeat(song.heat),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ 相关视频

  Widget _buildVideoRow(BuildContext context, RelatedVideo video) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildVideoCover(context, video),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title.trim().isEmpty ? '相关视频' : video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _videoSubtitle(video),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.play_circle_outline_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCover(BuildContext context, RelatedVideo video) {
    final duration = widget.song.durationSeconds;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 80,
        height: 45,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCover(
              context,
              video.coverUrl,
              cacheKey: 'hot-video-${video.bvid}',
              width: 80,
              height: 45,
            ),
            if (duration > 0)
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    formatDuration(Duration(seconds: duration)),
                    style: const TextStyle(fontSize: 9, color: Colors.white),
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

  Widget _buildCover(
    BuildContext context,
    String url, {
    required String cacheKey,
    required double width,
    required double height,
  }) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Icon(
        Icons.music_note,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );

    final trimmed = url.trim();
    if (trimmed.isEmpty) return placeholder;

    return CachedNetworkImage(
      imageUrl: trimmed,
      httpHeaders: NetworkConfig.biliHeaders,
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheManager: imageCacheManager,
      cacheKey: cacheKey,
      placeholder: (context, url) => placeholder,
      errorWidget: (context, url, error) => placeholder,
    );
  }

  static String _formatHeat(int heat) {
    if (heat >= 10000) return '${formatCount(heat)}热度';
    return '$heat 热度';
  }
}

/// 新上榜角标。
class _NewBadge extends StatelessWidget {
  final Color color;

  const _NewBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '新',
        style: TextStyle(
          fontSize: 9,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
