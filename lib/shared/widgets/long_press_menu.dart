import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/utils/share_helpers.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Builds a context menu for the given music.
///
/// [ref] 可选：传了就多一个「下载到离线缓存」项（需要 Provider 访问权限）。
/// 不传时菜单与历史行为一致——调用方是 [State]（没有 ref）时不必为此改结构。
Menu buildMusicContextMenu({
  required BuildContext context,
  required Music music,
  required PlayerCoordinator playerCoordinator,
  required PlaylistCommands commands,
  PlaylistService? playlistService,
  VoidCallback? onRemoveFromPlaylist,
  WidgetRef? ref,
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('开始播放"${music.title}"')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('播放失败: $e')));
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
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('添加下一首播放失败: $e')));
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
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已取消收藏')));
              }
            } else {
              await commands.addToFavorites(music);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已添加到收藏')));
              }
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('收藏操作失败: $e')));
            }
          }
        },
      ),
      MenuSeparator(),
      MenuAction(
        title: music.artist.name.trim().isEmpty
            ? '查看 UP 主'
            : music.artist.displayName,
        image: MenuImage.icon(Icons.person_outline),
        attributes: const MenuActionAttributes(),
        callback: () => _openArtist(context, music),
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
      if (ref != null)
        MenuAction(
          title: '离线缓存',
          image: MenuImage.icon(Icons.download_for_offline_outlined),
          callback: () =>
              performOfflineDownload(ref: ref, music: music, context: context),
        ),
      MenuAction(
        title: '分享',
        image: MenuImage.icon(Icons.share),
        callback: () => shareMusic(music),
      ),
      if (music.id.isNotEmpty)
        MenuAction(
          title: '打开原网页',
          image: MenuImage.icon(Icons.open_in_new),
          callback: () => openOriginalPage(music),
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
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('添加失败: $e')));
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

/// 打开 UP 页。
///
/// 条目上的 mid 常年可能为空（本地旧数据、非稿件来源），所以这里先过一遍
/// [ApiService.ensureMid]：缺 mid 才拉一次详情补齐，成功再跳页。
Future<void> _openArtist(BuildContext context, Music music) async {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  Music detailed;
  try {
    detailed = await ProviderScope.containerOf(context)
        .read(apiServiceProvider)
        .ensureMid(music);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('获取 UP 主信息失败: $e')));
    return;
  }
  if (!detailed.artist.hasMid) {
    messenger.showSnackBar(const SnackBar(content: Text('该稿件没有 UP 主信息')));
    return;
  }
  ShellPageManager.instance.goToArtist(
    up: UpProfile(
      mid: detailed.artist.mid,
      name: detailed.artist.name,
      face: detailed.artist.face,
    ),
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
    final sent = lanSvc.pushMusicToPeer(peer.id, detailed);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? '已推送到"${peer.name}"：${detailed.title}'
              : '推送失败："${peer.name}"未处于私有连接状态',
        ),
      ),
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
                // 跨 async gap 前先拿到 navigator 与 messenger
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await playlistService.createPlaylist(name: playlistName);
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('已创建歌单"$playlistName"')),
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('创建歌单失败: $e')));
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
  required VoidCallback onRename,
  required VoidCallback onDelete,
}) {
  return Menu(
    children: [
      MenuAction(
        title: '重命名',
        image: MenuImage.icon(Icons.edit_outlined),
        callback: onRename,
      ),
      MenuSeparator(),
      MenuAction(
        title: '删除',
        image: MenuImage.icon(Icons.delete_outline),
        attributes: const MenuActionAttributes(destructive: true),
        callback: onDelete,
      ),
    ],
  );
}

/// 弹出输入框，确认后把歌单改名为用户输入的名称并提示 SnackBar。
/// 判定条件与删除一致：系统/默认歌单由调用方跳过，
/// [PlaylistService.renamePlaylist] 内部也会再拦一次。
Future<void> confirmAndRenamePlaylist({
  required BuildContext context,
  required Playlist playlist,
  required PlaylistCommands commands,
}) async {
  final controller = TextEditingController(text: playlist.name);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
  final formKey = GlobalKey<FormState>();

  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('重命名歌单'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
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
          onFieldSubmitted: (_) {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );

  if (newName == null || newName == playlist.name) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await commands.renamePlaylist(playlist.id, newName);
    messenger.showSnackBar(SnackBar(content: Text('已将歌单重命名为"$newName"')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('重命名失败: $e')));
  }
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已删除歌单"$name"')));
  }
}
