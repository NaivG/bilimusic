import 'package:flutter/material.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/models/playlist.dart';

/// 左侧分类导航抽屉组件
class PlaylistSidebar extends StatelessWidget {
  final List<Playlist> playlists;
  final List<PlaylistTag> allTags;
  final String? selectedPlaylistId;
  final String? selectedTagId;
  final Function(String playlistId)? onPlaylistTap;
  final Function(String tagId)? onTagTap;
  final VoidCallback? onCreatePlaylist;
  final VoidCallback? onManageTags;

  const PlaylistSidebar({
    super.key,
    required this.playlists,
    required this.allTags,
    this.selectedPlaylistId,
    this.selectedTagId,
    this.onPlaylistTap,
    this.onTagTap,
    this.onCreatePlaylist,
    this.onManageTags,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 头部
          _buildHeader(context),
          // 内容
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // 系统歌单
                _buildSectionTitle(context, '音乐库'),
                _buildSystemPlaylists(context),
                const SizedBox(height: 16),
                // 我的歌单
                _buildSectionTitle(context, '我的歌单'),
                _buildUserPlaylists(context),
                const SizedBox(height: 16),
                // 标签分类
                _buildSectionTitle(context, '标签分类'),
                _buildTagCategories(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.library_music, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Text(
            '我的音乐',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
          if (title == '我的歌单' && onCreatePlaylist != null)
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: onCreatePlaylist,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildSystemPlaylists(BuildContext context) {
    final systemPlaylists = [
      DefaultPlaylists.favorites,
      DefaultPlaylists.history,
    ];

    return Column(
      children: systemPlaylists.map((playlist) {
        return _SidebarItem(
          icon: _getSystemPlaylistIcon(playlist.id),
          iconColor: _getSystemPlaylistColor(playlist.id),
          title: playlist.displayName,
          subtitle: '${playlist.songCount}首',
          isSelected: selectedPlaylistId == playlist.id,
          onTap: () => onPlaylistTap?.call(playlist.id),
        );
      }).toList(),
    );
  }

  Widget _buildUserPlaylists(BuildContext context) {
    if (playlists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '暂无歌单，点击 + 创建',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      );
    }

    return Column(
      children: playlists.map((playlist) {
        return _SidebarItem(
          icon: Icons.queue_music,
          title: playlist.name,
          subtitle: '${playlist.songCount}首',
          isSelected: selectedPlaylistId == playlist.id,
          onTap: () => onPlaylistTap?.call(playlist.id),
        );
      }).toList(),
    );
  }

  Widget _buildTagCategories(BuildContext context) {
    final tagsByCategory = <TagCategory, List<PlaylistTag>>{};
    for (final tag in allTags) {
      tagsByCategory.putIfAbsent(tag.category, () => []).add(tag);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 音乐风格
        _buildTagSection(
          context,
          '音乐风格',
          tagsByCategory[TagCategory.genre] ?? [],
        ),
        // 使用场景
        _buildTagSection(
          context,
          '使用场景',
          tagsByCategory[TagCategory.scenario] ?? [],
        ),
        // 心情情绪
        _buildTagSection(
          context,
          '心情情绪',
          tagsByCategory[TagCategory.mood] ?? [],
        ),
      ],
    );
  }

  Widget _buildTagSection(
    BuildContext context,
    String title,
    List<PlaylistTag> tags,
  ) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.only(left: 32),
      children: tags.map((tag) {
        return _SidebarItem(
          icon: tag.icon,
          iconColor: tag.color,
          title: tag.nameCn,
          isSelected: selectedTagId == tag.id,
          onTap: () => onTagTap?.call(tag.id),
          dense: true,
        );
      }).toList(),
    );
  }

  IconData _getSystemPlaylistIcon(String playlistId) {
    switch (playlistId) {
      case 'favorites':
        return Icons.favorite;
      case 'history':
        return Icons.history;
      case 'recommended':
        return Icons.auto_awesome;
      default:
        return Icons.library_music;
    }
  }

  Color _getSystemPlaylistColor(String playlistId) {
    switch (playlistId) {
      case 'favorites':
        return Colors.red;
      case 'history':
        return Colors.blue;
      case 'recommended':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

/// 侧边栏项组件
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool dense;

  const _SidebarItem({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.isSelected,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 8 : 12,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (iconColor ?? theme.colorScheme.primary).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: dense ? 18 : 20,
                  color: iconColor ?? theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: dense ? 13 : 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标签选择对话框
class TagSelectorDialog extends StatefulWidget {
  final List<String> selectedTagIds;
  final List<PlaylistTag> allTags;

  const TagSelectorDialog({
    super.key,
    required this.selectedTagIds,
    required this.allTags,
  });

  @override
  State<TagSelectorDialog> createState() => _TagSelectorDialogState();
}

class _TagSelectorDialogState extends State<TagSelectorDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedTagIds);
  }

  @override
  Widget build(BuildContext context) {
    final tagsByCategory = <TagCategory, List<PlaylistTag>>{};
    for (final tag in widget.allTags) {
      if (tag.category != TagCategory.custom) {
        tagsByCategory.putIfAbsent(tag.category, () => []).add(tag);
      }
    }

    return AlertDialog(
      title: const Text('选择标签'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            // 音乐风格
            _buildCategorySection(
              '音乐风格',
              tagsByCategory[TagCategory.genre] ?? [],
            ),
            // 使用场景
            _buildCategorySection(
              '使用场景',
              tagsByCategory[TagCategory.scenario] ?? [],
            ),
            // 心情情绪
            _buildCategorySection(
              '心情情绪',
              tagsByCategory[TagCategory.mood] ?? [],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedIds.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildCategorySection(String title, List<PlaylistTag> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            final isSelected = _selectedIds.contains(tag.id);
            return FilterChip(
              label: Text(tag.nameCn),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedIds.add(tag.id);
                  } else {
                    _selectedIds.remove(tag.id);
                  }
                });
              },
              avatar: Icon(tag.icon, size: 16, color: tag.color),
              selectedColor: tag.color.withValues(alpha: 0.2),
              checkmarkColor: tag.color,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
