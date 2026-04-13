import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';

/// 歌曲列表组件
class PlaylistSongList extends StatefulWidget {
  final List<Music> songs;
  final Music? currentPlayingMusic;
  final Function(Music) onSongTap;
  final Function(Music)? onSongLongPress;
  final Function(int, int)? onReorder;
  final Function(Music)? onRemove;
  final bool isEditable;
  final PlayerManager? playerManager;

  const PlaylistSongList({
    super.key,
    required this.songs,
    this.currentPlayingMusic,
    required this.onSongTap,
    this.onSongLongPress,
    this.onReorder,
    this.onRemove,
    this.isEditable = false,
    this.playerManager,
  });

  @override
  State<PlaylistSongList> createState() => _PlaylistSongListState();
}

class _PlaylistSongListState extends State<PlaylistSongList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        // 列表头部
        _buildListHeader(context),
        // 歌曲列表
        Expanded(
          child: widget.isEditable
              ? _buildReorderableList(context)
              : _buildNormalList(context),
        ),
      ],
    );
  }

  /// 空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '歌单为空',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '快去添加喜欢的音乐吧',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 列表头部
  Widget _buildListHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${widget.songs.length}首歌曲',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (widget.onReorder != null)
            TextButton.icon(
              onPressed: () {
                // TODO: 切换编辑模式
                setState(() {
                  _isSelectionMode = !_isSelectionMode;
                  if (!_isSelectionMode) {
                    _selectedIndices.clear();
                  }
                });
              },
              icon: Icon(_isSelectionMode ? Icons.check : Icons.edit, size: 16),
              label: Text(_isSelectionMode ? '完成' : '编辑'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  /// 普通列表
  Widget _buildNormalList(BuildContext context) {
    return ListView.builder(
      itemCount: widget.songs.length,
      itemExtent: 72, // 固定高度以提高性能
      itemBuilder: (context, index) {
        final music = widget.songs[index];
        final isPlaying = _isCurrentPlaying(music);
        final isSelected = _selectedIndices.contains(index);

        return _SongListTile(
          music: music,
          index: index,
          isPlaying: isPlaying,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          onTap: () => _handleTap(index),
          onLongPress: () => _handleLongPress(index),
          onCheckChanged: (selected) => _handleSelectionChange(index, selected),
        );
      },
    );
  }

  /// 可拖拽排序列表
  Widget _buildReorderableList(BuildContext context) {
    return ReorderableListView.builder(
      itemCount: widget.songs.length,
      itemExtent: 72,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        widget.onReorder?.call(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final scale = 1.0 + (animation.value * 0.05);
            return Transform.scale(scale: scale, child: child);
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final music = widget.songs[index];
        final isPlaying = _isCurrentPlaying(music);

        return _SongListTile(
          key: ValueKey(
            '${music.id}_${music.pages.isNotEmpty ? music.pages[0].cid : "0"}',
          ),
          music: music,
          index: index,
          isPlaying: isPlaying,
          isSelected: _selectedIndices.contains(index),
          isSelectionMode: _isSelectionMode,
          showDragHandle: widget.isEditable,
          onTap: () => _handleTap(index),
          onLongPress: () => _handleLongPress(index),
          onCheckChanged: (selected) => _handleSelectionChange(index, selected),
        );
      },
    );
  }

  bool _isCurrentPlaying(Music music) {
    if (widget.currentPlayingMusic == null) return false;
    return music.id == widget.currentPlayingMusic!.id &&
        (music.pages.isEmpty && widget.currentPlayingMusic!.pages.isEmpty ||
            music.pages.isNotEmpty &&
                widget.currentPlayingMusic!.pages.isNotEmpty &&
                music.pages[0].cid == widget.currentPlayingMusic!.pages[0].cid);
  }

  void _handleTap(int index) {
    if (_isSelectionMode) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      });
    } else {
      widget.onSongTap(widget.songs[index]);
    }
  }

  void _handleLongPress(int index) {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedIndices.add(index);
      });
    }
    widget.onSongLongPress?.call(widget.songs[index]);
  }

  void _handleSelectionChange(int index, bool selected) {
    setState(() {
      if (selected) {
        _selectedIndices.add(index);
      } else {
        _selectedIndices.remove(index);
      }
    });
  }
}

/// 单个歌曲项组件
class _SongListTile extends StatelessWidget {
  final Music music;
  final int index;
  final bool isPlaying;
  final bool isSelected;
  final bool isSelectionMode;
  final bool showDragHandle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool>? onCheckChanged;
  final PlayerManager? playerManager;
  final PlaylistManager? playlistManager;

  const _SongListTile({
    super.key,
    required this.music,
    required this.index,
    required this.isPlaying,
    required this.isSelected,
    required this.isSelectionMode,
    this.showDragHandle = false,
    required this.onTap,
    required this.onLongPress,
    this.onCheckChanged,
    this.playerManager,
    this.playlistManager,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isPlaying
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 选择框或序号
              if (isSelectionMode)
                Checkbox(
                  value: isSelected,
                  onChanged: (value) => onCheckChanged?.call(value ?? false),
                )
              else if (showDragHandle)
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                )
              else
                _buildIndex(context),
              const SizedBox(width: 12),
              // 封面
              _buildCover(context),
              const SizedBox(width: 12),
              // 歌曲信息
              Expanded(child: _buildInfo(context)),
              // 操作按钮
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 序号/播放指示器
  Widget _buildIndex(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    if (isPlaying) {
      // 播放中的波浪动画
      return SizedBox(width: 24, child: _PlayingIndicator());
    }

    return SizedBox(
      width: 24,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// 封面
  Widget _buildCover(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: music.safeCoverUrl,
            httpHeaders: NetworkConfig.biliHeaders,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                Container(width: 48, height: 48, color: Colors.grey[300]),
            errorWidget: (context, url, error) => Container(
              width: 48,
              height: 48,
              color: Colors.grey[300],
              child: const Icon(Icons.music_note),
            ),
            cacheManager: imageCacheManager,
          ),
        ),
        if (isPlaying)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Colors.black38,
              ),
              child: const Icon(Icons.equalizer, color: Colors.white, size: 20),
            ),
          ),
      ],
    );
  }

  /// 歌曲信息
  Widget _buildInfo(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = isPlaying
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          music.title,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (music.isFavorite)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.favorite,
                  size: 12,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            Expanded(
              child: Text(
                '${music.artist} · ${music.album}',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 操作按钮
  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showSongOptions(context),
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          iconSize: 20,
        ),
      ],
    );
  }

  void _showSongOptions(BuildContext context) {
    if (playerManager == null) {
      // 如果没有 PlayerManager，显示简化菜单
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: LongPressMenu(
          music: music,
          playerManager: playerManager!,
          playlistManager: playlistManager,
        ),
      ),
    );
  }
}

/// 播放指示器（波浪动画）
class _PlayingIndicator extends StatefulWidget {
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 400 + index * 100),
        vsync: this,
      )..repeat(reverse: true);
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(controller);
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              width: 3,
              height: 12 * _animations[index].value,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}

/// 排序方式选择器
class SortTypeSelector extends StatelessWidget {
  final PlaylistSortType currentSort;
  final ValueChanged<PlaylistSortType> onSortChanged;

  const SortTypeSelector({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PlaylistSortType>(
      initialValue: currentSort,
      onSelected: onSortChanged,
      icon: const Icon(Icons.sort),
      itemBuilder: (context) => [
        _buildMenuItem(PlaylistSortType.custom, '默认顺序'),
        _buildMenuItem(PlaylistSortType.nameAsc, '标题升序'),
        _buildMenuItem(PlaylistSortType.nameDesc, '标题降序'),
        _buildMenuItem(PlaylistSortType.dateAsc, '添加时间升序'),
        _buildMenuItem(PlaylistSortType.dateDesc, '添加时间降序'),
      ],
    );
  }

  PopupMenuItem<PlaylistSortType> _buildMenuItem(
    PlaylistSortType type,
    String label,
  ) {
    return PopupMenuItem(
      value: type,
      child: Row(
        children: [
          if (currentSort == type)
            const Icon(Icons.check, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
