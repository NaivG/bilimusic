import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_hero.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_song_list.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 歌单页共享骨架：歌单头 + 曲目卡。
///
/// 横竖屏只差 Hero 方向与左右边距；横屏通栏，边距由壳层给。
class PlaylistContent extends ConsumerWidget {
  const PlaylistContent({
    super.key,
    required this.isLandscape,
    required this.songs,
    required this.isLiked,
    required this.onSongTap,
    required this.onToggleLike,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onAddToPlaylist,
    required this.onExportEntries,
    required this.onImportEntries,
    required this.onOfflineCacheAll,
    this.playlistId,
    this.currentPlaylist,
    this.onRemoveSong,
    this.onRemoveMany,
    this.canImportEntries = true,
  });

  /// 首屏折叠预览行数（设计稿一次露 7 行）。
  static const int _previewRows = 7;

  final bool isLandscape;
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final bool isLiked;
  final Function(Music) onSongTap;
  final VoidCallback onToggleLike;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onExportEntries;
  final VoidCallback onImportEntries;
  final VoidCallback onOfflineCacheAll;
  final Function(Music)? onRemoveSong;
  final Future<bool> Function(List<Music>)? onRemoveMany;
  final bool canImportEntries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horizontal = isLandscape ? BmTokens.contentInset : BmTokens.pageInset;
    final playlist = currentPlaylist ?? _fallbackPlaylist();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            isLandscape ? 0 : BmTokens.s3,
            horizontal,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: PlaylistHero(
              playlist: playlist,
              songs: songs,
              isLandscape: isLandscape,
              isLiked: isLiked,
              onPlayAll: onPlayAll,
              onShufflePlay: onShufflePlay,
              onToggleLike: onToggleLike,
              onAddToPlaylist: onAddToPlaylist,
              onExportEntries: onExportEntries,
              onImportEntries: onImportEntries,
              onOfflineCacheAll: onOfflineCacheAll,
              canImportEntries: canImportEntries,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: BmTokens.s4)),
        PlaylistSongList(
          songs: songs,
          currentPlayingMusic: ref.watch(currentMusicProvider),
          onSongTap: onSongTap,
          isEditable: playlistId != null,
          onRemove: playlistId != null ? onRemoveSong : null,
          onRemoveMany: playlistId != null ? onRemoveMany : null,
          isLandscape: isLandscape,
          previewLimit: _previewRows,
          horizontalInset: horizontal,
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: isLandscape ? 0 : BmTokens.s6),
        ),
        // 给竖屏浮动的迷你播放器 / Dock 让位；横屏该值即底部安全区。
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }

  /// 未拿到歌单详情时的兜底（搜索结果等临时列表）。
  Playlist _fallbackPlaylist() {
    final now = DateTime.now();
    return Playlist(id: 'temp', name: '播放列表', createdAt: now, updatedAt: now);
  }
}
