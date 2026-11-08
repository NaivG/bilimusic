import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';

/// 横屏模式新侧边栏 - 基于ParticleMusic风格
///
/// Chrome 材质：右边 hairline + 可选背景模糊；顶层导航、离线、喜欢、
/// 历史与歌单统一走 [BmNavRow]，选中态由 [selectedLabel] / [selectedPlaylistId]
/// 决定。
class LandscapeSidebar extends ConsumerWidget {
  /// 侧栏宽度；标题栏搜索框以其右缘为左对齐基准。
  static const double width = 221;

  /// 顶层导航（首页/发现/设置）当前高亮标签；进入歌单页时为 null，
  /// 使任何顶层导航项都不显示高亮，让被点击的歌单独占视觉焦点。
  final String? selectedLabel;
  final List<Playlist> playlists;
  final String? selectedPlaylistId;
  final Function(String label) onNavTap;
  final Function(String playlistId)? onPlaylistTap;
  final VoidCallback? onCreatePlaylist;

  const LandscapeSidebar({
    super.key,
    required this.selectedLabel,
    required this.playlists,
    this.selectedPlaylistId,
    required this.onNavTap,
    this.onPlaylistTap,
    this.onCreatePlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );

    return SizedBox(
      width: width,
      child: BmChromeSurface(
        edges: const <BmChromeEdge>{BmChromeEdge.right},
        blur: blur,
        child: Column(
          children: [
            const SizedBox(height: BmTokens.s2),
            // 导航内容
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: BmTokens.s2),
                children: [
                  // 首页（用户态主页）
                  _buildNavRow(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    title: '首页',
                    selected: selectedLabel == 'home',
                    onTap: () => onNavTap('home'),
                  ),
                  // 发现（平台榜单/推荐）
                  _buildNavRow(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore,
                    title: '发现',
                    selected: selectedLabel == 'discover',
                    onTap: () => onNavTap('discover'),
                  ),
                  const SizedBox(height: BmTokens.s2),
                  Divider(
                    height: BmTokens.s1 / 2,
                    thickness: BmTokens.hairlineWidth,
                    indent: BmTokens.s5,
                    endIndent: BmTokens.s5,
                    color: colors.hairline,
                  ),
                  const SizedBox(height: BmTokens.s2),
                  // 我喜欢的音乐
                  _buildNavRow(
                    icon: Icons.favorite_outline,
                    activeIcon: Icons.favorite,
                    title: '我喜欢的音乐',
                    selected: selectedPlaylistId == 'favorites',
                    onTap: () => onPlaylistTap?.call('favorites'),
                  ),
                  // 最近播放
                  _buildNavRow(
                    icon: Icons.history,
                    title: '最近播放',
                    selected: selectedPlaylistId == 'history',
                    onTap: () => onPlaylistTap?.call('history'),
                  ),
                  // 离线缓存
                  _buildNavRow(
                    icon: Icons.download_outlined,
                    activeIcon: Icons.download,
                    title: '离线缓存',
                    selected: selectedLabel == 'offline',
                    onTap: () => onNavTap('offline'),
                  ),
                  const SizedBox(height: BmTokens.s2),
                  Divider(
                    height: BmTokens.s1 / 2,
                    thickness: BmTokens.hairlineWidth,
                    indent: BmTokens.s5,
                    endIndent: BmTokens.s5,
                    color: colors.hairline,
                  ),
                  const SizedBox(height: BmTokens.s2),
                  // 创建的歌单
                  _buildPlaylistSection(context, ref),
                ],
              ),
            ),
            // 设置
            _buildNavRow(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              title: '设置',
              selected: selectedLabel == 'settings',
              onTap: () => onNavTap('settings'),
            ),
            const SizedBox(height: BmTokens.s2),
          ],
        ),
      ),
    );
  }

  /// 统一的侧栏导航行：左右留白后交给 [BmNavRow] 画选中条与状态层。
  Widget _buildNavRow({
    required IconData icon,
    IconData? activeIcon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
      child: BmNavRow(
        icon: icon,
        activeIcon: activeIcon,
        title: title,
        selected: selected,
        onTap: onTap,
      ),
    );
  }

  Widget _buildPlaylistSection(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 歌单头部
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s5,
            vertical: BmTokens.s1 / 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '创建的歌单',
                style: type.micro.copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              if (onCreatePlaylist != null)
                BmIconButton(
                  icon: Icons.add,
                  tooltip: '创建歌单',
                  size: BmIconButtonSize.sm,
                  onPressed: onCreatePlaylist,
                ),
            ],
          ),
        ),
        // 歌单列表
        ...playlists.map((p) {
          final row = Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
            child: BmNavRow(
              icon: Icons.queue_music,
              title: p.name,
              selected: selectedPlaylistId == p.id,
              trailing: Text(
                '${p.songCount}首',
                style: type.caption.copyWith(color: colors.textTertiary),
              ),
              onTap: () => onPlaylistTap?.call(p.id),
            ),
          );
          final MenuProvider? contextMenuBuilder = p.isDefault
              ? null
              : (_) => buildPlaylistContextMenu(
                  context: context,
                  playlist: p,
                  onRename: () => confirmAndRenamePlaylist(
                    context: context,
                    playlist: p,
                    commands: ref.read(playlistCommandsProvider.notifier),
                  ),
                  onDelete: () => confirmAndDeletePlaylist(
                    context: context,
                    playlist: p,
                    commands: ref.read(playlistCommandsProvider.notifier),
                  ),
                );
          if (contextMenuBuilder == null) return row;
          return AppContextMenu(menuProvider: contextMenuBuilder, child: row);
        }),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.s5,
              vertical: BmTokens.s2,
            ),
            child: Text(
              '暂无歌单',
              style: type.caption.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    );
  }
}
