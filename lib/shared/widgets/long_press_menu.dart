import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/utils/share_helpers.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Builds a context menu for the given music.
FutureOr<Menu?> buildMusicContextMenu({
  required BuildContext context,
  required Music music,
  required PlayerCoordinator playerCoordinator,
  required PlaylistCommands commands,
  PlaylistService? playlistService,
  VoidCallback? onRemoveFromPlaylist,
}) {
  final isFav = commands.isFavorite(music);

  return Menu(
    children: [
      MenuAction(
        title: '播放',
        image: MenuImage.icon(Icons.play_arrow),
        callback: () async {
          try {
            await playerCoordinator.playMusic(music);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('开始播放"${music.title}"')),
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
            await playerCoordinator.playNextFromIndex(music);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已添加到下一首播放"${music.title}"')),
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
              await commands.removeFromFavorites(music);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已取消收藏')));
              }
            } else {
              await commands.addToFavorites(music);
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
      if (playlistService != null) ...[
        MenuSeparator(),
        _buildAddToPlaylistSubmenu(context, music, playlistService),
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
      _buildPushToDeviceSubmenu(context, music),
      MenuSeparator(),
      MenuAction(
        title: '分享',
        image: MenuImage.icon(Icons.share),
        callback: () => shareMusic(music),
      ),
    ],
  );
}

Menu _buildAddToPlaylistSubmenu(
  BuildContext context,
  Music music,
  PlaylistService playlistService,
) {
  List<Playlist> userPlaylists = [];
  try {
    userPlaylists = playlistService.userPlaylistsSnapshot;
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
        callback: () => _createNewPlaylist(context, playlistService),
      ),
      if (userPlaylists.isNotEmpty) MenuSeparator(),
      ...userPlaylists.map(
        (playlist) => MenuAction(
          title: playlist.name,
          callback: () async {
            try {
              await playlistService.addSongToUserPlaylist(playlist.id, music);
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

/// 构建"推送到设备"子菜单。
///
/// 仅列出已配对 + 已连接 + 对端模式为 private 的对端；
/// 没有可推设备时仍保留外壳并显示 disabled "暂无可用设备"，
/// 避免用户不知道该功能存在。
Menu _buildPushToDeviceSubmenu(BuildContext context, Music music) {
  List<PeerDevice> eligible = const [];
  try {
    final container = ProviderScope.containerOf(context);
    final peersAsync = container.read(peersProvider);
    final peers = peersAsync.asData?.value ?? const <PeerDevice>[];
    eligible =
        peers
            .where(
              (p) =>
                  p.isPaired && p.isConnected && p.mode == LanSyncMode.private,
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
  } catch (_) {
    // riverpod 不可用（如 widget 被脱离 ProviderScope 测试）—— 当作无可用设备
    eligible = const [];
  }

  return Menu(
    title: '推送到设备',
    image: MenuImage.icon(Icons.cast_connected),
    children: [
      if (eligible.isEmpty)
        MenuAction(
          title: '暂无可用设备',
          attributes: const MenuActionAttributes(disabled: true),
          callback: () {},
        )
      else
        ...eligible.map(
          (peer) => MenuAction(
            title: peer.name,
            image: MenuImage.icon(_platformIcon(peer.platform)),
            callback: () => _pushToDevice(context, music, peer),
          ),
        ),
    ],
  );
}

Future<void> _pushToDevice(
  BuildContext context,
  Music music,
  PeerDevice peer,
) async {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context);
  final lanSvc = container.read(lanSyncServiceProvider);
  try {
    // 推送前补齐 cid，保证对端拿到即可播放
    final detailed = await container.read(apiServiceProvider).ensureCid(music);
    lanSvc.pushMusicToPeer(peer.id, detailed);
    messenger.showSnackBar(
      SnackBar(content: Text('已推送到"${peer.name}"：${detailed.title}')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('推送失败: $e')));
  }
}

/// 为对端平台选一个粗略的图标：mobile / desktop / 其它。
IconData _platformIcon(String platform) {
  switch (platform) {
    case 'android':
    case 'ios':
      return Icons.smartphone;
    case 'windows':
    case 'macos':
    case 'linux':
      return Icons.desktop_mac;
    default:
      return Icons.devices;
  }
}

void _createNewPlaylist(BuildContext context, PlaylistService playlistService) {
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
                  await playlistService.createPlaylist(name: playlistName);
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

/// 长按歌单列表项时弹出的上下文菜单。
/// 调用方应在用户歌单(非系统歌单)上调用;系统歌单无需包裹 ContextMenuWidget。
Menu buildPlaylistContextMenu({
  required BuildContext context,
  required Playlist playlist,
  required VoidCallback onDelete,
}) {
  return Menu(
    children: [
      MenuAction(
        title: '删除歌单',
        image: MenuImage.icon(Icons.delete_outline),
        attributes: const MenuActionAttributes(destructive: true),
        callback: onDelete,
      ),
    ],
  );
}

/// 弹出确认对话框,确认后调用 [commands] 删除歌单并提示 SnackBar。
/// 三个调用点复用,避免重复实现 AlertDialog 样板。
Future<void> confirmAndDeletePlaylist({
  required BuildContext context,
  required Playlist playlist,
  required PlaylistCommands commands,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('确认删除'),
      content: Text('确定要删除歌单"${playlist.name}"吗?此操作不可撤销'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final name = playlist.name;
  await commands.deletePlaylist(playlist.id);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除歌单"$name"')));
  }
}
