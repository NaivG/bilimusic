import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/components/common/cards/music_list_item.dart';

/// 歌曲列表组件
class PlaylistSongList extends StatelessWidget {
  final List<Music> songs;
  final Music? currentPlayingMusic;
  final Function(Music) onSongTap;
  final Function(Music)? onSongLongPress;
  final Function(int, int)? onReorder;
  final Function(Music)? onRemove;
  final bool isEditable;

  const PlaylistSongList({
    super.key,
    required this.songs,
    this.currentPlayingMusic,
    required this.onSongTap,
    this.onSongLongPress,
    this.onReorder,
    this.onRemove,
    this.isEditable = false,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        _buildListHeader(context),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '歌单为空',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '快去添加喜欢的音乐吧',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '${songs.length}首歌曲',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (onReorder != null)
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('编辑'),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (isEditable && onReorder != null) {
      return ReorderableListView.builder(
        itemCount: songs.length,
        itemExtent: 64,
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
        itemBuilder: (context, index) {
          final music = songs[index];
          final isPlaying = _isCurrentPlaying(music);
          return MusicListItem(
            key: ValueKey('${music.id}_${music.pages.isNotEmpty ? music.pages[0].cid : "0"}'),
            music: music,
            index: index,
            isPlaying: isPlaying,
            isFavorite: music.isFavorite,
            playerManager: sl.playerManager,
            onTap: () => onSongTap(music),
          );
        },
      );
    }

    return ListView.builder(
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
    );
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
