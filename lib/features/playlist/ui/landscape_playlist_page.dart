import 'package:flutter/material.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/ui/playlist_content.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';

/// 横屏歌单页：通栏，标题栏与左右边距由壳层给。
class LandscapePlaylistPage extends StatelessWidget {
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final bool isLiked;
  final Function(Music) onSongTap;
  final Function(Music)? onRemoveSong;
  final Future<bool> Function(List<Music>)? onRemoveMany;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onToggleLike;
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
    this.isLiked = false,
    required this.onSongTap,
    this.onRemoveSong,
    this.onRemoveMany,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onExportEntries,
    required this.onImportEntries,
    required this.onOfflineCacheAll,
    this.canImportEntries = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 透出壳层背景。
      backgroundColor: context.bmColors.bg.withValues(alpha: 0),
      body: PlaylistContent(
        isLandscape: true,
        playlistId: playlistId,
        songs: songs,
        currentPlaylist: currentPlaylist,
        isLiked: isLiked,
        onSongTap: onSongTap,
        onRemoveSong: onRemoveSong,
        onRemoveMany: onRemoveMany,
        onPlayAll: onPlayAll,
        onShufflePlay: onShufflePlay,
        onToggleLike: onToggleLike,
        onAddToPlaylist: onAddToPlaylist,
        onExportEntries: onExportEntries,
        onImportEntries: onImportEntries,
        onOfflineCacheAll: onOfflineCacheAll,
        canImportEntries: canImportEntries,
      ),
    );
  }
}
