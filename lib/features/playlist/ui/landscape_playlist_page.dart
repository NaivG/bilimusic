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
  final Function(Music) onSongTap;
  final Function(Music)? onRemoveSong;
  final Future<bool> Function(List<Music>)? onRemoveMany;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onExportEntries;
  final VoidCallback onImportEntries;
  final VoidCallback onOfflineCacheAll;
  final bool canImportEntries;

  const LandscapePlaylistPage({
    super.key,
    this.playlistId,
    required this.songs,
    this.currentPlaylist,
    required this.onSongTap,
    this.onRemoveSong,
    this.onRemoveMany,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onAddToPlaylist,
    required this.onExportEntries,
    required this.onImportEntries,
    required this.onOfflineCacheAll,
    this.canImportEntries = true,
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
                      onPlayAll: onPlayAll,
                      onShufflePlay: onShufflePlay,
                      onAddToPlaylist: onAddToPlaylist,
                      onExportEntries: onExportEntries,
                      onImportEntries: onImportEntries,
                      onOfflineCacheAll: onOfflineCacheAll,
                      canImportEntries: canImportEntries,
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
                    onRemoveMany: playlistId != null ? onRemoveMany : null,
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
