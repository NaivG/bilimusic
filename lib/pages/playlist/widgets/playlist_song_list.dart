import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Enhanced song list for playlist page.
/// Supports search bar, table headers (landscape), track rows with
/// index/title/duration/heart, editable reorder, and long-press menu.
class PlaylistSongList extends StatelessWidget {
  final List<Music> songs;
  final Music? currentPlayingMusic;
  final Function(Music) onSongTap;
  final Function(int, int)? onReorder;
  final Function(Music)? onRemove;
  final bool isEditable;
  final bool isLandscape;

  const PlaylistSongList({
    super.key,
    required this.songs,
    this.currentPlayingMusic,
    required this.onSongTap,
    this.onReorder,
    this.onRemove,
    this.isEditable = false,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState(context));
    }

    if (isEditable && onReorder != null) {
      return _buildReorderableList(context);
    }

    return _buildSliverList(context);
  }

  Widget _buildEmptyState(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_off,
            size: 80,
            color: LucentTokens.textTertiary(brightness),
          ),
          const SizedBox(height: 16),
          Text(
            '歌单为空',
            style: TextStyle(
              fontSize: 18,
              color: LucentTokens.textSecondary(brightness),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '快去添加喜欢的音乐吧',
            style: TextStyle(
              fontSize: 14,
              color: LucentTokens.textTertiary(brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: LucentTokens.borderSubtle(brightness),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // #
          SizedBox(
            width: 32,
            child: Text(
              '#',
              style: TextStyle(
                fontSize: 11,
                color: LucentTokens.textTertiary(brightness),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // TITLE
          Expanded(
            child: Text(
              'TITLE',
              style: TextStyle(
                fontSize: 11,
                color: LucentTokens.textTertiary(brightness),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Duration
          SizedBox(
            width: 48,
            child: Icon(
              Icons.access_time,
              size: 14,
              color: LucentTokens.textTertiary(brightness),
            ),
          ),
          // Heart placeholder
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSliverList(BuildContext context) {
    if (isLandscape) {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == 0) return _buildTableHeader(context);
          final music = songs[index - 1];
          return SizedBox(
            height: 56,
            child: PlaylistTrackRow(
              music: music,
              index: index - 1,
              isPlaying: _isCurrentPlaying(music),
              isLandscape: isLandscape,
              onTap: () => onSongTap(music),
              onRemoveFromPlaylist: isEditable && onRemove != null
                  ? () => onRemove?.call(music)
                  : null,
            ),
          );
        }, childCount: songs.length + 1),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final music = songs[index];
        return PlaylistTrackRow(
          music: music,
          index: index,
          isPlaying: _isCurrentPlaying(music),
          isLandscape: isLandscape,
          onTap: () => onSongTap(music),
          onRemoveFromPlaylist: isEditable && onRemove != null
              ? () => onRemove?.call(music)
              : null,
        );
      }, childCount: songs.length),
    );
  }

  Widget _buildReorderableList(BuildContext context) {
    final slivers = <Widget>[];
    if (isLandscape) {
      slivers.add(SliverToBoxAdapter(child: _buildTableHeader(context)));
    }
    slivers.add(
      SliverReorderableList(
        itemExtent: 56,
        itemBuilder: (context, index) {
          final music = songs[index];
          return PlaylistTrackRow(
            key: ValueKey(
              '${music.id}_${music.pages.isNotEmpty ? music.pages[0].cid : "0"}',
            ),
            music: music,
            index: index,
            isPlaying: _isCurrentPlaying(music),
            isLandscape: isLandscape,
            onTap: () => onSongTap(music),
            onRemoveFromPlaylist: onRemove != null
                ? () => onRemove?.call(music)
                : null,
          );
        },
        itemCount: songs.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex--;
          onReorder?.call(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final scale = 1.0 + (animation.value * 0.05);
              return Transform.scale(scale: scale, child: child);
            },
            child: child,
          );
        },
      ),
    );
    return SliverMainAxisGroup(slivers: slivers);
  }

  bool _isCurrentPlaying(Music music) {
    if (currentPlayingMusic == null) return false;
    return music.id == currentPlayingMusic!.id &&
        (music.pages.isEmpty && currentPlayingMusic!.pages.isEmpty ||
            music.pages.isNotEmpty &&
                currentPlayingMusic!.pages.isNotEmpty &&
                music.pages[0].cid == currentPlayingMusic!.pages[0].cid);
  }
}

/// Track row widget for playlist song list.
/// Shows index, title (with artist subtitle), duration, and heart icon.
class PlaylistTrackRow extends StatefulWidget {
  final Music music;
  final int index;
  final bool isPlaying;
  final bool isLandscape;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveFromPlaylist;

  const PlaylistTrackRow({
    super.key,
    required this.music,
    required this.index,
    this.isPlaying = false,
    this.isLandscape = false,
    this.onTap,
    this.onRemoveFromPlaylist,
  });

  @override
  State<PlaylistTrackRow> createState() => _PlaylistTrackRowState();
}

class _PlaylistTrackRowState extends State<PlaylistTrackRow> {
  bool _isHovered = false;

  String _formatDuration(Music music) {
    if (music.duration != null) {
      final d = music.duration!;
      return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    if (music.pages.isNotEmpty) {
      return music.pages[0].formattedDuration;
    }
    return '--:--';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return ContextMenuWidget(
      menuProvider: (_) => buildMusicContextMenu(
        context: context,
        music: widget.music,
        playerCoordinator: sl.playerCoordinator,
        onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: LucentTokens.standardDuration,
            curve: Curves.easeOutCubic,
            height: 56,
            decoration: BoxDecoration(
              color: _isHovered
                  ? LucentTokens.surfaceHover(brightness)
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: LucentTokens.borderSubtle(brightness),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Index
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${widget.index + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.isPlaying
                            ? LucentTokens.accentPrimary
                            : LucentTokens.textTertiary(brightness),
                        fontWeight: widget.isPlaying
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Title + artist subtitle
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.music.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: widget.isPlaying
                                ? LucentTokens.accentPrimary
                                : LucentTokens.textPrimary(brightness),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.music.artist} - ${widget.music.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: LucentTokens.textTertiary(brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Duration
                  SizedBox(
                    width: 48,
                    child: Text(
                      _formatDuration(widget.music),
                      style: TextStyle(
                        fontSize: 13,
                        color: LucentTokens.textSecondary(brightness),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Heart icon
                  Icon(
                    widget.music.isFavorite
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 16,
                    color: widget.music.isFavorite
                        ? LucentTokens.accentError
                        : LucentTokens.textTertiary(brightness),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
