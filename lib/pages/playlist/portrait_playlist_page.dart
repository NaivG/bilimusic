import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_header.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_song_list.dart';

/// 竖屏播放列表页面
class PortraitPlaylistPage extends StatefulWidget {
  final String? playlistId;
  final List<Music> songs;
  final Playlist? currentPlaylist;
  final List<Playlist> userPlaylists;
  final List<PlaylistTag> allTags;
  final String? selectedTagId;
  final bool isFavorited;
  final VoidCallback onBack;
  final Function(Music) onSongTap;
  final Function(Music) onSongLongPress;
  final Function(Music) onRemoveSong;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onToggleFavorite;
  final Function(String) onFilterByTag;
  final VoidCallback onCreatePlaylist;

  const PortraitPlaylistPage({
    super.key,
    this.playlistId,
    required this.songs,
    this.currentPlaylist,
    required this.userPlaylists,
    required this.allTags,
    this.selectedTagId,
    required this.isFavorited,
    required this.onBack,
    required this.onSongTap,
    required this.onSongLongPress,
    required this.onRemoveSong,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onToggleFavorite,
    required this.onFilterByTag,
    required this.onCreatePlaylist,
  });

  @override
  State<PortraitPlaylistPage> createState() => _PortraitPlaylistPageState();
}

class _PortraitPlaylistPageState extends State<PortraitPlaylistPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // 歌单信息头部
              PlaylistHeader(
                playlist:
                    widget.currentPlaylist ??
                    Playlist(
                      id: 'temp',
                      name: '播放列表',
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                songs: widget.songs,
                onPlayAll: widget.onPlayAll,
                onShufflePlay: widget.onShufflePlay,
                onFavorite: widget.onToggleFavorite,
                isFavorited: widget.isFavorited,
              ),
              const SizedBox(height: 16),
              // 歌曲列表
              Expanded(
                child: PlaylistSongList(
                  songs: widget.songs,
                  currentPlayingMusic: sl.playerManager.currentMusic,
                  onSongTap: widget.onSongTap,
                  onSongLongPress: widget.onSongLongPress,
                  isEditable: widget.playlistId != null,
                  onRemove: widget.playlistId != null
                      ? widget.onRemoveSong
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
