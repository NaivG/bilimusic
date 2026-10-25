import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 行内「更多」菜单按钮。
///
/// 菜单内容与右键/长按的 [buildMusicContextMenu] 完全一致，只是改成
/// 点击按钮后以 Material 菜单弹出，便于触屏和没有右键习惯的用户。
class MusicMenuButton extends ConsumerStatefulWidget {
  final Music music;
  final VoidCallback? onRemoveFromPlaylist;

  const MusicMenuButton({
    super.key,
    required this.music,
    this.onRemoveFromPlaylist,
  });

  @override
  ConsumerState<MusicMenuButton> createState() => _MusicMenuButtonState();
}

class _MusicMenuButtonState extends ConsumerState<MusicMenuButton> {
  final MenuController _controller = MenuController();
  List<Widget>? _menuChildren;
  bool _openScheduled = false;

  void _toggleMenu() {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    if (_openScheduled) return;

    // 菜单内容依赖收藏状态 / 当前歌单等实时数据，每次打开都重新构建。
    setState(() {
      _menuChildren = _buildMenuChildren();
    });
    _openScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openScheduled = false;
      if (mounted) _controller.open();
    });
  }

  List<Widget> _buildMenuChildren() {
    final menu = buildMusicContextMenu(
      context: context,
      music: widget.music,
      playerCoordinator: ref.read(playerCoordinatorProvider),
      commands: ref.read(playlistCommandsProvider.notifier),
      onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
      ref: ref,
    );
    return _convertElements(menu.children);
  }

  /// 把 super_context_menu 的菜单模型转换成 Material 菜单项。
  List<Widget> _convertElements(List<MenuElement> elements) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconTheme = IconThemeData(
      size: 18,
      color: colorScheme.onSurfaceVariant,
    );
    final children = <Widget>[];

    for (final element in elements) {
      if (element is MenuSeparator) {
        children.add(
          Divider(height: 9, thickness: 1, color: colorScheme.outlineVariant),
        );
      } else if (element is MenuAction) {
        final destructive = element.attributes.destructive;
        children.add(
          MenuItemButton(
            onPressed: element.attributes.disabled ? null : element.callback,
            leadingIcon: element.image?.asWidget(
              destructive
                  ? iconTheme.copyWith(color: colorScheme.error)
                  : iconTheme,
            ),
            child: Text(
              element.title ?? '',
              style: destructive ? TextStyle(color: colorScheme.error) : null,
            ),
          ),
        );
      } else if (element is Menu) {
        children.add(
          SubmenuButton(
            menuChildren: _convertElements(element.children),
            leadingIcon: element.image?.asWidget(iconTheme),
            child: Text(element.title ?? ''),
          ),
        );
      }
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      menuChildren: _menuChildren ?? const [],
      builder: (context, controller, child) => IconButton(
        onPressed: _toggleMenu,
        icon: const Icon(Icons.more_horiz),
        iconSize: 18,
        color: colorScheme.onSurfaceVariant,
        tooltip: '更多',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      ),
    );
  }
}
