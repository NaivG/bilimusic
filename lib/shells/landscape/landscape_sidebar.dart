import 'package:flutter/material.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/models/playlist.dart';

/// 横屏模式侧边栏：仿网易云音乐风格 - 推荐 + 我的音乐 + 歌单
class LandscapeSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<Playlist> playlists;
  final List<PlaylistTag> allTags;
  final String? selectedPlaylistId;
  final Function(int index) onNavTap;
  final Function(String playlistId)? onPlaylistTap;
  final VoidCallback? onCreatePlaylist;

  const LandscapeSidebar({
    super.key,
    required this.selectedIndex,
    required this.playlists,
    required this.allTags,
    this.selectedPlaylistId,
    required this.onNavTap,
    this.onPlaylistTap,
    this.onCreatePlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 200,
      color: isDark ? const Color(0xFF1a1a1a) : const Color(0xFFF8F8F8),
      child: Column(
        children: [
          // 推荐区域
          _buildRecommendSection(context),
          const Divider(height: 1),
          // 我的音乐区域
          _buildMyMusicSection(context),
          const Divider(height: 1),
          // 歌单列表（可滚动）
          Expanded(child: _buildPlaylistSection(context)),
        ],
      ),
    );
  }

  Widget _buildRecommendSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            '推荐',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              letterSpacing: 0.5,
            ),
          ),
        ),
        _NavTile(
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore,
          label: '发现',
          isActive: selectedIndex == 0,
          onTap: () => onNavTap(0),
        ),
        _NavTile(
          icon: Icons.podcasts_outlined,
          activeIcon: Icons.podcasts,
          label: '播客',
          isActive: selectedIndex == 0,
          onTap: () => onNavTap(0),
        ),
        _NavTile(
          icon: Icons.public_outlined,
          activeIcon: Icons.public,
          label: '漫游',
          isActive: selectedIndex == 0,
          onTap: () => onNavTap(0),
        ),
        _NavTile(
          icon: Icons.people_outline,
          activeIcon: Icons.people,
          label: '关注',
          isActive: selectedIndex == 0,
          onTap: () => onNavTap(0),
        ),
      ],
    );
  }

  Widget _buildMyMusicSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            '我的音乐',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              letterSpacing: 0.5,
            ),
          ),
        ),
        _NavTile(
          icon: Icons.favorite_outline,
          activeIcon: Icons.favorite,
          label: '我喜欢',
          iconColor: Colors.red,
          isActive: selectedPlaylistId == 'favorites',
          onTap: () => onPlaylistTap?.call('favorites'),
        ),
        _NavTile(
          icon: Icons.history_outlined,
          activeIcon: Icons.history,
          label: '最近播放',
          iconColor: Colors.blue,
          isActive: selectedPlaylistId == 'history',
          onTap: () => onPlaylistTap?.call('history'),
        ),
        _NavTile(
          icon: Icons.podcasts_outlined,
          activeIcon: Icons.podcasts,
          label: '我的播客',
          isActive: selectedPlaylistId == 'podcasts',
          onTap: () => onPlaylistTap?.call('podcasts'),
        ),
        _NavTile(
          icon: Icons.star_outline,
          activeIcon: Icons.star,
          label: '我的收藏',
          isActive: selectedPlaylistId == 'favorites',
          onTap: () => onPlaylistTap?.call('favorites'),
        ),
      ],
    );
  }

  Widget _buildPlaylistSection(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '创建的歌单',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  letterSpacing: 0.5,
                ),
              ),
              if (onCreatePlaylist != null)
                GestureDetector(
                  onTap: onCreatePlaylist,
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
        // 用户歌单
        ...playlists.map(
          (p) => _PlaylistTile(
            icon: Icons.queue_music,
            title: p.name,
            subtitle: '${p.songCount}首',
            isSelected: selectedPlaylistId == p.id,
            onTap: () => onPlaylistTap?.call(p.id),
          ),
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '暂无歌单',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;

  _NavItem(this.icon, this.activeIcon, this.label, this.index);
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final Color? iconColor;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.iconColor,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 网易云音乐品牌红色
    const neteaseRed = Color(0xFFEC407A);

    final effectiveIcon = isActive ? (activeIcon ?? icon) : icon;
    final effectiveColor = isActive
        ? neteaseRed
        : (iconColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.65));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isActive
            ? neteaseRed.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(effectiveIcon, size: 18, color: effectiveColor),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? neteaseRed
                        : (isDark
                              ? Colors.white70
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.8,
                                )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback? onTap;

  const _PlaylistTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color:
                      iconColor ??
                      theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
