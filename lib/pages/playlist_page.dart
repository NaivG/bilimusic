import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/player_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/utils/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/components/playlist_manager.dart';
import 'package:bilimusic/components/long_press_menu.dart';

class PlaylistPage extends StatefulWidget {
  final List<Music>? songs; // 可选的直接传入歌曲列表
  final String? playlistId; // 播放列表ID（用于用户自定义播放列表）
  final String playlistName;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager; // 播放列表管理器

  const PlaylistPage({
    super.key,
    this.songs,
    this.playlistId,
    required this.playlistName,
    required this.playerManager,
    this.playlistManager,
  }) : assert(songs != null || playlistId != null, 'Either songs or playlistId must be provided');

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Music> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  /// 加载歌曲列表
  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.songs != null) {
        // 直接使用传入的歌曲列表（适用于特殊播放列表，如播放历史、我的收藏等）
        _songs = List.from(widget.songs!);
      } else if (widget.playlistId != null && widget.playlistManager != null) {
        // 从播放列表管理器加载歌曲（适用于用户自定义播放列表）
        _songs = await widget.playlistManager!.getPlaylistSongs(widget.playlistId!);
      }
    } catch (e) {
      debugPrint('Failed to load songs: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 从播放列表中移除歌曲
  Future<void> _removeSong(int index) async {
    if (widget.playlistId != null && widget.playlistManager != null) {
      final songToRemove = _songs[index];
      
      // 显示确认对话框
      final confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定要从歌单中移除"${songToRemove.title}"吗？'),
            actions: <Widget>[
              TextButton(
                child: const Text('取消'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('删除'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      );
      
      // 如果用户确认删除
      if (confirm == true) {
        await widget.playlistManager!.removeSongFromPlaylist(widget.playlistId!, songToRemove);
        setState(() {
          _songs.removeAt(index);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从歌单中移除"${songToRemove.title}"')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此歌单不支持删除操作')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 头图部分
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.playlistName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              background: _songs.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // 背景图片
                        CachedNetworkImage(
                          imageUrl: _songs[0].safeCoverUrl,
                          httpHeaders: NetworkConfig.biliHeaders,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.image_not_supported_rounded),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          cacheManager: imageCacheManager,
                          cacheKey: _songs[0].id,
                        ),
                        // 渐变遮罩
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black45,
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: Theme.of(context).primaryColor,
                      child: const Center(
                        child: Icon(
                          Icons.music_note,
                          size: 50,
                          color: Colors.white70,
                        ),
                      ),
                    ),
            ),
          ),
          
          // 信息显示按钮
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // 播放全部按钮
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _songs.isNotEmpty
                          ? () async {
                              // 清空当前播放列表并添加所有歌曲
                              await widget.playerManager.clearPlayList();
                              await widget.playerManager.addAllToPlayList(_songs);
                              
                              // 播放第一首歌曲
                              if (_songs.isNotEmpty) {
                                await widget.playerManager.play(widget.playerManager.playList[0]);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text('播放全部(${_songs.length})'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 添加歌曲按钮（暂时不做逻辑）
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      // TODO: 实现添加歌曲功能
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('添加歌曲功能尚未实现')),
                      );
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 歌曲列表
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (_isLoading) {
                  return const ListTile(
                    title: Text('加载中...'),
                  );
                }
                
                final music = _songs[index];
                return GestureDetector(
                  onTap: () async {
                    // 播放选中的歌曲
                    await widget.playerManager.play(music);
                  },
                  onLongPress: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: LongPressMenu(
                          music: music,
                          playerManager: widget.playerManager,
                          playlistManager: widget.playlistManager,
                        ),
                      ),
                    );
                  },
                  onSecondaryTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          contentPadding: const EdgeInsets.all(16.0),
                          content: LongPressMenu(
                            music: music,
                            playerManager: widget.playerManager,
                            playlistManager: widget.playlistManager,
                          ),
                        );
                      },
                    );
                  },
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: music.safeCoverUrl,
                        httpHeaders:
                            Map<String, String>.from(NetworkConfig.biliHeaders),
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.image_not_supported_rounded),
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        cacheManager: imageCacheManager,
                        cacheKey: music.id,
                      ),
                    ),
                    title: Text(music.title),
                    subtitle: Text('${music.artist} - ${music.album}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        _removeSong(index);
                      },
                    ),
                  ),
                );
              },
              childCount: _isLoading ? 1 : _songs.length,
            ),
          ),
        ],
      ),
    );
  }
}