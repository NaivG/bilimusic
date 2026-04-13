import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_header.dart';
import 'package:bilimusic/pages/playlist/widgets/playlist_song_list.dart';

/// 竖屏播放列表页面
class PortraitPlaylistPage extends StatefulWidget {
  final String? playlistId;
  final List<Music> songs;
  final PlayerManager playerManager;
  final PlaylistManager playlistManager;
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
    required this.playerManager,
    required this.playlistManager,
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

class _PortraitPlaylistPageState extends State<PortraitPlaylistPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: PlaylistHeader(
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
            ),
          ];
        },
        body: Column(
          children: [
            // TabBar
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '歌曲列表'),
                  Tab(text: '评论'),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 歌曲列表
                  PlaylistSongList(
                    songs: widget.songs,
                    currentPlayingMusic: widget.playerManager.currentMusic,
                    onSongTap: widget.onSongTap,
                    onSongLongPress: widget.onSongLongPress,
                    isEditable: widget.playlistId != null,
                    onReorder: widget.playlistId != null
                        ? (oldIndex, newIndex) {
                            // TODO: 实现拖拽排序
                          }
                        : null,
                    onRemove:
                        widget.playlistId != null ? widget.onRemoveSong : null,
                  ),
                  // 评论占位
                  _buildCommentsPlaceholder(),
                ],
              ),
            ),
          ],
        ),
      ),
      drawer: widget.playlistId == null
          ? null
          : PlaylistSidebar(
              playlists: widget.userPlaylists,
              allTags: widget.allTags,
              selectedPlaylistId: widget.playlistId,
              selectedTagId: widget.selectedTagId,
              onPlaylistTap: (playlistId) {
                Navigator.pop(context);
                // TODO: 导航到对应歌单
              },
              onTagTap: widget.onFilterByTag,
              onCreatePlaylist: widget.onCreatePlaylist,
            ),
    );
  }

  Widget _buildCommentsPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.comment_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '评论功能开发中',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// 播放列表侧边栏
class PlaylistSidebar extends StatelessWidget {
  final List<Playlist> playlists;
  final List<PlaylistTag> allTags;
  final String? selectedPlaylistId;
  final String? selectedTagId;
  final Function(String) onPlaylistTap;
  final Function(String) onTagTap;
  final VoidCallback onCreatePlaylist;

  const PlaylistSidebar({
    super.key,
    required this.playlists,
    required this.allTags,
    this.selectedPlaylistId,
    this.selectedTagId,
    required this.onPlaylistTap,
    required this.onTagTap,
    required this.onCreatePlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '我的歌单',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: onCreatePlaylist,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  final isSelected = playlist.id == selectedPlaylistId;
                  return ListTile(
                    leading: Icon(
                      playlist.systemPlaylistIcon ?? Icons.music_note,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      playlist.name,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('${playlist.songCount}首'),
                    selected: isSelected,
                    onTap: () => onPlaylistTap(playlist.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
