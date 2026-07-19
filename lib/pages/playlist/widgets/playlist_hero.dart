import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/theme/app_palette.dart';
import 'package:bilimusic/theme/app_tokens.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

/// Lucent-style hero section for playlist page.
/// Displays cover art, metadata, pill buttons, and action icons.
/// Switches between landscape (Row) and portrait (Column) layout.
class PlaylistHero extends StatelessWidget {
  final Playlist playlist;
  final List<Music> songs;
  final bool isLandscape;
  final bool isFavorited;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onToggleFavorite;

  const PlaylistHero({
    super.key,
    required this.playlist,
    this.songs = const [],
    required this.isLandscape,
    this.isFavorited = false,
    this.onPlayAll,
    this.onShufflePlay,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return isLandscape
        ? _buildLandscapeLayout(context)
        : _buildPortraitLayout(context);
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCover(context, 180),
          const SizedBox(width: 32),
          Expanded(child: _buildInfoAndActions(context)),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          _buildCover(context, 220),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildInfoAndActions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context, double size) {
    final coverUrl = playlist.safeCoverUrl;
    final systemIcon = playlist.systemPlaylistIcon;
    final systemIconColor = playlist.systemPlaylistIconColor;
    final songCount = songs.length;
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;

    return Hero(
      tag: 'playlist_cover_${playlist.id}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (systemIcon != null)
                Container(
                  color:
                      systemIconColor?.withValues(alpha: 0.15) ??
                      palette.surfaceHover,
                  child: Center(
                    child: Icon(
                      systemIcon,
                      size: size * 0.4,
                      color:
                          systemIconColor ?? colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else if (coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  httpHeaders: NetworkConfig.biliHeaders,
                  placeholder: (_, _) => Container(
                    color: palette.surfaceHover,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: palette.surfaceHover,
                    child: Icon(
                      Icons.music_note,
                      size: size * 0.3,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  fit: BoxFit.cover,
                  cacheManager: imageCacheManager,
                )
              else
                Container(
                  color: palette.surfaceHover,
                  child: Icon(
                    Icons.music_note,
                    size: size * 0.3,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              // Song count badge
              if (songCount > 0 && systemIcon == null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, color: Colors.white, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          '$songCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoAndActions(BuildContext context) {
    final songCount = songs.length;
    final totalMinutes = songs.fold<int>(
      0,
      (sum, m) => sum + (m.duration?.inSeconds ?? 0),
    );
    final minutes = totalMinutes ~/ 60;
    final seconds = totalMinutes % 60;
    final colorScheme = Theme.of(context).colorScheme;

    // Compute total duration text
    String durationText;
    if (playlist.formattedDuration.isNotEmpty) {
      durationText = playlist.formattedDuration;
    } else if (totalMinutes > 0) {
      durationText = seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
    } else {
      durationText = '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "专辑" label
        Text(
          '专辑',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        // Title
        Text(
          playlist.displayName,
          style: TextStyle(
            fontSize: isLandscape ? 24 : 22,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // Metadata row (note icon + count + duration)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '${songCount > 0 ? songCount : playlist.songCount}首曲目',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (durationText.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '·',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                durationText,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        // Artist
        if (songs.isNotEmpty && songs.first.artist.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            songs.first.artist,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 20),
        // Pill buttons
        _buildPillButtons(context),
        const SizedBox(height: 12),
        // Action icons
        _buildActionIcons(context),
      ],
    );
  }

  Widget _buildPillButtons(BuildContext context) {
    final hasSongs = songs.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        // Play all button
        SizedBox(
          height: 36,
          child: ElevatedButton.icon(
            onPressed: hasSongs ? onPlayAll : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('播放', style: TextStyle(fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              disabledBackgroundColor: palette.surfaceHover,
              disabledForegroundColor: colorScheme.onSurfaceVariant,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              elevation: 0,
            ),
          ),
        ),
        // Add to playlist button
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: hasSongs ? () {} : null,
            icon: Icon(
              Icons.playlist_add,
              size: 18,
              color: hasSongs
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            label: Text(
              '添加到播放列表',
              style: TextStyle(
                fontSize: 14,
                color: hasSongs
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              side: BorderSide(
                color: hasSongs
                    ? colorScheme.primary.withValues(alpha: 0.4)
                    : colorScheme.outline,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionIcons(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Favorite toggle
        IconButton(
          onPressed: onToggleFavorite,
          icon: Icon(
            isFavorited ? Icons.favorite : Icons.favorite_border,
            color: isFavorited
                ? colorScheme.error
                : colorScheme.onSurfaceVariant,
            size: 22,
          ),
          tooltip: isFavorited ? '取消收藏' : '收藏',
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(40, 40),
          ),
        ),
        const SizedBox(width: 4),
        // More options
        IconButton(
          onPressed: () {},
          icon: Icon(
            Icons.more_horiz,
            color: colorScheme.onSurfaceVariant,
            size: 22,
          ),
          tooltip: '更多',
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(40, 40),
          ),
        ),
      ],
    );
  }
}