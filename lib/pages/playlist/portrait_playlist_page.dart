import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_hero.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_song_list.dart';

/// Portrait playlist page with hero Column + track list in a single scroll.
class PortraitPlaylistPage extends ConsumerWidget {
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final bool isFavorited;
  final VoidCallback onBack;
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
    required this.onBack,
    required this.onSongTap,
    this.onRemoveSong,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;

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
                color: LucentTokens.borderSubtle(brightness),
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
