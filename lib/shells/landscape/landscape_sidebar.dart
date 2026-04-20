import 'package:flutter/material.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/utils/color_infra.dart';

/// 横屏模式新侧边栏 - 基于ParticleMusic风格
class LandscapeSidebar extends StatelessWidget {
  final String selectedLabel;
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
  Widget build(BuildContext context) {
    return Material(
      // color: landscapeSidebarColor.withValues(alpha: 0.7),
      color: Colors.transparent,
      child: SizedBox(
        width: 221,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: BoxBorder.fromLTRB(
              right: BorderSide(color: iconColor.withValues(alpha: 0.1)),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              // 导航内容
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // 发现音乐
                    _SidebarItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      label: '发现',
                      isSelected: selectedLabel == 'home',
                      onTap: () => onNavTap('home'),
                    ),
                    // 搜索
                    _SidebarItem(
                      icon: Icons.search,
                      activeIcon: Icons.search,
                      label: '搜索',
                      isSelected: selectedLabel == 'search',
                      onTap: () => onNavTap('search'),
                    ),
                    const SizedBox(height: 10),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 20,
                      endIndent: 20,
                    ),
                    const SizedBox(height: 10),
                    // 我喜欢的音乐
                    _SidebarItem(
                      icon: Icons.favorite_outline,
                      activeIcon: Icons.favorite,
                      label: '我喜欢的音乐',
                      iconColor: Colors.red,
                      isSelected: selectedPlaylistId == 'favorites',
                      onTap: () => onPlaylistTap?.call('favorites'),
                    ),
                    // 最近播放
                    _SidebarItem(
                      icon: Icons.history,
                      activeIcon: Icons.history,
                      label: '最近播放',
                      iconColor: Colors.blue,
                      isSelected: selectedPlaylistId == 'history',
                      onTap: () => onPlaylistTap?.call('history'),
                    ),
                    const SizedBox(height: 10),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 20,
                      endIndent: 20,
                    ),
                    const SizedBox(height: 10),
                    // 创建的歌单
                    _buildPlaylistSection(),
                  ],
                ),
              ),
              // 设置
              _SidebarItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: '设置',
                isSelected: selectedLabel == 'settings',
                onTap: () => onNavTap('settings'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 歌单头部
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '创建的歌单',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.45),
                  letterSpacing: 0.5,
                ),
              ),
              if (onCreatePlaylist != null)
                GestureDetector(
                  onTap: onCreatePlaylist,
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: textColor.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
        // 歌单列表
        ...playlists.map(
          (p) => _PlaylistItem(
            title: p.name,
            subtitle: '${p.songCount}首',
            isSelected: selectedPlaylistId == p.id,
            onTap: () => onPlaylistTap?.call(p.id),
          ),
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              '暂无歌单',
              style: TextStyle(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.35),
              ),
            ),
          ),
      ],
    );
  }
}

/// 侧边栏导航项
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final Color? iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = isSelected ? (activeIcon ?? icon) : icon;
    final effectiveColor = isSelected
        ? selectedItemColor
        : (iconColor ?? iconColor?.withValues(alpha: 0.65));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: isSelected
              ? selectedItemColor.withValues(alpha: 0.15)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(effectiveIcon, size: 24, color: effectiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? highlightTextColor
                            : textColor.withValues(alpha: 0.8),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 歌单项
class _PlaylistItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback? onTap;

  const _PlaylistItem({
    required this.title,
    this.subtitle,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: isSelected
              ? selectedItemColor.withValues(alpha: 0.15)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 22,
                    color: isSelected
                        ? highlightTextColor
                        : textColor.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? highlightTextColor
                            : textColor.withValues(alpha: 0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.45),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
