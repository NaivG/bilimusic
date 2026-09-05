import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_hero.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_song_list.dart';

/// Portrait playlist page with hero Column + track list in a single scroll.
class PortraitPlaylistPage extends ConsumerWidget {
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final bool isFavorited;
  final Function(Music) onSongTap;
  final Function(Music)? onRemoveSong;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onToggleFavorite;

  const PortraitPlaylistPage({
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
      body: CustomScrollView(
        slivers: [
          // Top spacing
          SliverToBoxAdapter(child: SizedBox(height: 8)),
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
              isLandscape: false,
              isFavorited: isFavorited,
              onPlayAll: onPlayAll,
              onShufflePlay: onShufflePlay,
              onToggleFavorite: onToggleFavorite,
            ),
          ),
          // Divider between hero and track list
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outline,
              ),
            ),
          ),
          // Track list
          PlaylistSongList(
            songs: songs,
            currentPlayingMusic: ref.watch(currentMusicProvider),
            onSongTap: onSongTap,
            isEditable: playlistId != null,
            onRemove: playlistId != null ? onRemoveSong : null,
            isLandscape: false,
          ),
        ],
      ),
    );
  }
}
