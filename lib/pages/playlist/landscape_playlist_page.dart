import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_header.dart';
import 'package:bilimusic/components/common/cards/music_list_item.dart';

/// 横屏播放列表页面
class LandscapePlaylistPage extends StatelessWidget {
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final bool isFavorited;
  final VoidCallback onBack;
  final Function(Music) onSongTap;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onToggleFavorite;

  const LandscapePlaylistPage({
    super.key,
    this.playlistId,
    required this.songs,
    this.currentPlaylist,
    this.isFavorited = false,
    required this.onBack,
    required this.onSongTap,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: Row(
                children: [
                  // 左侧歌单信息
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(
                        LandscapeBreakpoints.getHorizontalPadding(context),
                      ),
                      child: PlaylistHeader(
                        playlist:
                            currentPlaylist ??
                            Playlist(
                              id: 'temp',
                              name: '播放列表',
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                            ),
                        songs: songs,
                        onPlayAll: onPlayAll,
                        onShufflePlay: onShufflePlay,
                        onFavorite: onToggleFavorite,
                        isFavorited: isFavorited,
                      ),
                    ),
                  ),
                  // 右侧歌曲列表
                  Expanded(
                    flex: 1,
                    child: _buildRightSection(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(
        horizontal: LandscapeBreakpoints.getHorizontalPadding(context) / 2,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 24),
            ),
            onPressed: onBack,
          ),
          const Spacer(),
          Text(
            currentPlaylist?.displayName ?? '播放列表',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildRightSection(BuildContext context) {
    final horizontalPadding = LandscapeBreakpoints.getHorizontalPadding(context);

    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        children: [
          _buildListHeader(context, horizontalPadding),
          Expanded(
            child: songs.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding / 2,
                      vertical: 8,
                    ),
                    itemCount: songs.length,
                    itemExtent: 64,
                    itemBuilder: (context, index) {
                      final music = songs[index];
                      final isPlaying = _isCurrentPlaying(music);
                      return MusicListItem(
                        music: music,
                        index: index,
                        isPlaying: isPlaying,
                        isFavorite: music.isFavorite,
                        playerManager: sl.playerManager,
                        onTap: () => onSongTap(music),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context, double horizontalPadding) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding / 2, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            '歌曲列表',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${songs.length}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            '歌单为空',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
        ],
      ),
    );
  }

  bool _isCurrentPlaying(Music music) {
    final currentMusic = sl.playerManager.currentMusic;
    if (currentMusic == null) return false;
    return music.id == currentMusic.id &&
        (music.pages.isEmpty && currentMusic.pages.isEmpty ||
            music.pages.isNotEmpty &&
                currentMusic.pages.isNotEmpty &&
                music.pages[0].cid == currentMusic.pages[0].cid);
  }
}
