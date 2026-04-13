import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:share_plus/share_plus.dart';

class LongPressMenu extends StatefulWidget {
  final Music music;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onRemoveFromPlaylist;

  const LongPressMenu({
    super.key,
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.onRemoveFromPlaylist,
  });

  @override
  State<LongPressMenu> createState() => _LongPressMenuState();
}

class _LongPressMenuState extends State<LongPressMenu> {
  List<Playlist> _userPlaylists = [];

  @override
  void initState() {
    super.initState();
    _loadUserPlaylists();
  }

  Future<void> _loadUserPlaylists() async {
    if (widget.playlistManager != null) {
      try {
        final playlists = widget.playlistManager!.getAllPlaylists();
        setState(() {
          _userPlaylists = playlists;
        });
      } catch (e) {
        debugPrint('Failed to load user playlists: $e');
      }
    }
  }

  /// 创建新播放列表
  Future<void> _createNewPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建新歌单'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '歌单名称',
                hintText: '请输入歌单名称',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入歌单名称';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final playlistName = controller.text.trim();
                  try {
                    await widget.playlistManager!.createPlaylist(playlistName);
                    Navigator.of(context).pop();
                    await _loadUserPlaylists();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已创建歌单"$playlistName"')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('创建歌单失败: $e')));
                    }
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  /// 显示添加到歌单的菜单
  Future<void> _showAddToPlaylistMenu(BuildContext context) async {
    if (widget.playlistManager == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放列表管理器不可用')));
      return;
    }

    await _loadUserPlaylists();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '添加到歌单',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add, color: Colors.blue),
                title: const Text('新建歌单'),
                onTap: () {
                  Navigator.pop(context);
                  _createNewPlaylist(context);
                },
              ),
              const Divider(),
              Expanded(
                child: _userPlaylists.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('暂无歌单'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _userPlaylists.length,
                        itemBuilder: (context, index) {
                          final playlist = _userPlaylists[index];
                          return ListTile(
                            title: Text(playlist.name),
                            subtitle: Text(
                              '创建于: ${playlist.createdAt.toString().split(' ').first}',
                            ),
                            onTap: () async {
                              try {
                                await widget.playlistManager!.addSongToPlaylist(
                                  playlist.id,
                                  widget.music,
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已添加到歌单"${playlist.name}"'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('添加失败: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 600 ? 600 : double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 音乐信息部分
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: widget.music.safeCoverUrl,
                      httpHeaders: NetworkConfig.biliHeaders,
                      placeholder: (context, url) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[300],
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[300],
                        child: const Icon(Icons.music_note),
                      ),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      cacheManager: imageCacheManager,
                      cacheKey: widget.music.id,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.music.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.music.artist} - ${widget.music.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        kDebugMode
                            ? Text(
                                '${widget.music} id: ${widget.music.id}-${widget.music.cid}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 菜单选项部分
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.play_arrow, color: Colors.blue),
                  title: const Text('播放'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      final detailedMusic = await widget.music
                          .getVideoDetails();
                      await widget.playerManager.play(detailedMusic);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('开始播放"${detailedMusic.title}"'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('播放失败: $e')));
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play, color: Colors.green),
                  title: const Text('下一首播放'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      final detailedMusic = await widget.music
                          .getVideoDetails();
                      // 使用新的playNextFromIndex方法将歌曲添加到下一首播放
                      await widget.playerManager.playNextFromIndex(
                        detailedMusic,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已添加到下一首播放"${detailedMusic.title}"'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('添加下一首播放失败: $e')),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    widget.playerManager.isFavorite(widget.music)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: widget.playerManager.isFavorite(widget.music)
                        ? Colors.red
                        : null,
                  ),
                  title: Text(
                    widget.playerManager.isFavorite(widget.music)
                        ? '取消收藏'
                        : '收藏',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      if (widget.playerManager.isFavorite(widget.music)) {
                        await widget.playerManager.removeFromFavorites(
                          widget.music,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已取消收藏')),
                          );
                        }
                      } else {
                        await widget.playerManager.addToFavorites(widget.music);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已添加到收藏')),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('收藏操作失败: $e')));
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add, color: Colors.orange),
                  title: const Text('添加到歌单'),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (widget.playlistManager != null) {
                      _showAddToPlaylistMenu(context);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('播放列表功能不可用')),
                        );
                      }
                    }
                  },
                ),
                if (widget.onRemoveFromPlaylist != null)
                  ListTile(
                    leading: const Icon(
                      Icons.playlist_remove,
                      color: Colors.red,
                    ),
                    title: const Text(
                      '从歌单中移除',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onRemoveFromPlaylist?.call();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.share, color: Colors.blue),
                  title: const Text('分享'),
                  onTap: () {
                    Navigator.of(context).pop();
                    final String shareText =
                        '由 BiliMusic 分享：${widget.music.title}\n'
                        'https://b23.tv/${widget.music.id}';
                    SharePlus.instance.share(
                      ShareParams(
                        text: shareText,
                        sharePositionOrigin: Rect.fromCenter(
                          center: Offset.zero,
                          width: 100,
                          height: 100,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
