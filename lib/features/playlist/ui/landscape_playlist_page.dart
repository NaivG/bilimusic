import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_hero.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_song_list.dart';

/// Landscape playlist page with hero Row + track list in a single scroll.
class LandscapePlaylistPage extends ConsumerWidget {
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final bool isFavorited;
  final Function(Music) onSongTap;
  final Function(Music)? onRemoveSong;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onToggleFavorite;

  const LandscapePlaylistPage({
    super.key,
    this.playlistId,
    required this.songs,
    this.currentPlaylist,
    this.isFavorited = false,
    required this.onSongTap,
    this.onRemoveSong,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // appbar is handled by landscape_title_bar
            // _buildAppBar(context, brightness),
            // Scrollable content
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Hero section
                  SliverToBoxAdapter(
                    child: PlaylistHero(
                      playlist:
                          currentPlaylist ??
                          Playlist(
                            id: 'temp',
                            name: '播放列表',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          ),
                      songs: songs,
                      isLandscape: true,
                      isFavorited: isFavorited,
                      onPlayAll: onPlayAll,
                      onShufflePlay: onShufflePlay,
                      onToggleFavorite: onToggleFavorite,
                    ),
                  ),
                  // Divider between hero and track list
                  SliverToBoxAdapter(
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: colorScheme.outline,
                      indent: 24,
                      endIndent: 24,
                    ),
                  ),
                  // Track list
                  PlaylistSongList(
                    songs: songs,
                    currentPlayingMusic: ref.watch(currentMusicProvider),
                    onSongTap: onSongTap,
                    isEditable: playlistId != null,
                    onRemove: playlistId != null ? onRemoveSong : null,
                    isLandscape: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
