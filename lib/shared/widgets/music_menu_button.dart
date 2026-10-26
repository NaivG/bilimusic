import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/widgets/app_menu_button.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';

/// 行内「更多」菜单按钮。
///
/// 菜单内容与右键/长按的 [buildMusicContextMenu] 完全一致，桌面端点击后
/// 弹出与右键菜单相同样式的浮层，触屏端则使用底部操作单。
class MusicMenuButton extends ConsumerWidget {
  final Music music;
  final VoidCallback? onRemoveFromPlaylist;

  const MusicMenuButton({
    super.key,
    required this.music,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppMenuButton(
      menuBuilder: (context) => buildMusicContextMenu(
        context: context,
        music: music,
        playerCoordinator: ref.read(playerCoordinatorProvider),
        commands: ref.read(playlistCommandsProvider.notifier),
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        ref: ref,
      ),
      color: colorScheme.onSurfaceVariant,
      iconSize: 18,
      tooltip: '更多',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }
}
