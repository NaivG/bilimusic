import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Builds a context menu for the given music.
FutureOr<Menu?> buildMusicContextMenu({
  required BuildContext context,
  required Music music,
  required PlayerCoordinator playerCoordinator,
  PlaylistManager? playlistManager,
  VoidCallback? onRemoveFromPlaylist,
}) {
  final isFav = playerCoordinator.isFavorite(music);

  return Menu(
    children: [
      MenuAction(
        title: '播放',
        image: MenuImage.icon(Icons.play_arrow),
        callback: () async {
          try {
            final detailedMusic = await music.getVideoDetails();
            await playerCoordinator.playMusic(detailedMusic);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('开始播放"${detailedMusic.title}"')),
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
      MenuAction(
        title: '下一首播放',
        image: MenuImage.icon(Icons.playlist_play),
        callback: () async {
          try {
            final detailedMusic = await music.getVideoDetails();
            await playerCoordinator.playNextFromIndex(detailedMusic);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已添加到下一首播放"${detailedMusic.title}"')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('添加下一首播放失败: $e')));
            }
          }
        },
      ),
      MenuAction(
        title: isFav ? '取消收藏' : '收藏',
        image: MenuImage.icon(isFav ? Icons.favorite : Icons.favorite_border),
        callback: () async {
          try {
            if (isFav) {
              await playerCoordinator.removeFromFavorites(music);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已取消收藏')));
              }
            } else {
              await playerCoordinator.addToFavorites(music);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已添加到收藏')));
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
      if (playlistManager != null) ...[
        MenuSeparator(),
        _buildAddToPlaylistSubmenu(context, music, playlistManager),
      ],
      if (onRemoveFromPlaylist != null) ...[
        MenuSeparator(),
        MenuAction(
          title: '从歌单中移除',
          image: MenuImage.icon(Icons.playlist_remove),
          attributes: const MenuActionAttributes(destructive: true),
          callback: () => onRemoveFromPlaylist(),
        ),
      ],
      MenuSeparator(),
      MenuAction(
        title: '分享',
        image: MenuImage.icon(Icons.share),
        callback: () {
          final String shareText =
              '由 BiliMusic 分享：${music.title}\n'
              'https://b23.tv/${music.id}';
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
  );
}

Menu _buildAddToPlaylistSubmenu(
  BuildContext context,
  Music music,
  PlaylistManager playlistManager,
) {
  List<Playlist> userPlaylists = [];
  try {
    userPlaylists = playlistManager.getAllPlaylists();
  } catch (e) {
    debugPrint('Failed to load user playlists: $e');
  }

  return Menu(
    title: '添加到歌单',
    image: MenuImage.icon(Icons.playlist_add),
    children: [
      MenuAction(
        title: '新建歌单',
        image: MenuImage.icon(Icons.add),
        callback: () => _createNewPlaylist(context, playlistManager),
      ),
      if (userPlaylists.isNotEmpty) MenuSeparator(),
      ...userPlaylists.map(
        (playlist) => MenuAction(
          title: playlist.name,
          callback: () async {
            try {
              await playlistManager.addSongToPlaylist(playlist.id, music);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已添加到歌单"${playlist.name}"')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('添加失败: $e')));
              }
            }
          },
        ),
      ),
      if (userPlaylists.isEmpty)
        MenuAction(
          title: '暂无歌单',
          attributes: const MenuActionAttributes(disabled: true),
          callback: () {},
        ),
    ],
  );
}

void _createNewPlaylist(BuildContext context, PlaylistManager playlistManager) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  showDialog(
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
                  await playlistManager.createPlaylist(playlistName);
                  Navigator.of(context).pop();
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
  ).then((_) => controller.dispose());
}
