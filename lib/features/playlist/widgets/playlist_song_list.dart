import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';
import 'package:bilimusic/shared/widgets/music_menu_button.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Enhanced song list for playlist page.
/// Supports search bar, list headers with multi-select, track rows with
/// index/title/duration/heart, editable reorder, and long-press menu.
class PlaylistSongList extends ConsumerStatefulWidget {
  final List<Music> songs;
  final Music? currentPlayingMusic;
  final Function(Music) onSongTap;
  final Function(int, int)? onReorder;
  final Function(Music)? onRemove;

  /// 批量删除回调，返回是否实际删除。
  ///
  /// 非空时列表头显示「多选」入口。
  final Future<bool> Function(List<Music>)? onRemoveMany;
  final bool isEditable;
  final bool isLandscape;

  const PlaylistSongList({
    super.key,
    required this.songs,
    this.currentPlayingMusic,
    required this.onSongTap,
    this.onReorder,
    this.onRemove,
    this.onRemoveMany,
    this.isEditable = false,
    this.isLandscape = false,
  });

  @override
  ConsumerState<PlaylistSongList> createState() => _PlaylistSongListState();
}

class _PlaylistSongListState extends ConsumerState<PlaylistSongList> {
  bool _selectionMode = false;
  bool _isDeleting = false;
  final Set<String> _selectedKeys = <String>{};

  List<Music> get _selectedSongs =>
      widget.songs.where((music) => _selectedKeys.contains(music.key)).toList();

  @override
  void didUpdateWidget(covariant PlaylistSongList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_selectionMode) return;

    final validKeys = widget.songs.map((music) => music.key).toSet();
    _selectedKeys.removeWhere((key) => !validKeys.contains(key));
    if (widget.songs.isEmpty) {
      _selectionMode = false;
      _selectedKeys.clear();
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedKeys.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedKeys.clear();
    });
  }

  void _toggleSelection(Music music) {
    setState(() {
      if (!_selectedKeys.remove(music.key)) {
        _selectedKeys.add(music.key);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedSongs.length == widget.songs.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys.addAll(widget.songs.map((music) => music.key));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final songs = _selectedSongs;
    final onRemoveMany = widget.onRemoveMany;
    if (songs.isEmpty || onRemoveMany == null || _isDeleting) return;

    setState(() => _isDeleting = true);
    var removed = false;
    try {
      removed = await onRemoveMany(songs);
    } catch (_) {
      // 错误提示由回调方负责，这里只恢复按钮状态。
    }
    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      if (removed) {
        _selectionMode = false;
        _selectedKeys.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState(context));
    }

    final slivers = <Widget>[];
    if (widget.isLandscape || widget.onRemoveMany != null) {
      slivers.add(SliverToBoxAdapter(child: _buildListHeader(context)));
    }

    if (widget.isEditable && widget.onReorder != null && !_selectionMode) {
      slivers.add(_buildReorderableList(context));
    } else {
      slivers.add(_buildSliverList(context));
    }

    return SliverMainAxisGroup(slivers: slivers);
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 80, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            '歌单为空',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '快去添加喜欢的音乐吧',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: widget.isLandscape ? 4 : 6,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      child: _selectionMode
          ? _buildSelectionHeader(context)
          : _buildColumnHeader(context),
    );
  }

  Widget _buildColumnHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 11,
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );

    if (!widget.isLandscape) {
      return Row(
        children: [
          Text('${widget.songs.length} 首曲目', style: labelStyle),
          const Spacer(),
          if (widget.onRemoveMany != null) _buildMultiSelectButton(context),
        ],
      );
    }

    return Row(
      children: [
        // #
        SizedBox(width: 32, child: Text('#', style: labelStyle)),
        // TITLE
        Expanded(child: Text('TITLE', style: labelStyle)),
        // Duration
        SizedBox(
          width: 48,
          child: Icon(
            Icons.access_time,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        // 行尾「下一首播放」+「更多」按钮占位
        SizedBox(
          width: 70,
          child: widget.onRemoveMany == null
              ? null
              : Align(
                  alignment: Alignment.centerRight,
                  child: _buildMultiSelectButton(context),
                ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextButton.icon(
      onPressed: _enterSelectionMode,
      icon: const Icon(Icons.checklist, size: 14),
      label: const Text('多选'),
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildSelectionHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = _selectedSongs.length;
    final allSelected = count == widget.songs.length;

    return Row(
      children: [
        Text(
          '已选 $count 首',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.primary,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _isDeleting ? null : _toggleSelectAll,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: count == 0 || _isDeleting ? null : _deleteSelected,
          icon: _isDeleting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onError,
                  ),
                )
              : const Icon(Icons.delete_outline, size: 16),
          label: Text(count > 0 ? '删除 ($count)' : '删除'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
            disabledBackgroundColor: colorScheme.error.withValues(alpha: 0.25),
            disabledForegroundColor: colorScheme.onError.withValues(alpha: 0.7),
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: _isDeleting ? null : _exitSelectionMode,
          icon: const Icon(Icons.close, size: 18),
          tooltip: '退出多选',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        ),
      ],
    );
  }

  Widget _buildSliverList(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final music = widget.songs[index];
        return SizedBox(
          height: 56,
          child: _buildTrackRow(context, music, index),
        );
      }, childCount: widget.songs.length),
    );
  }

  Widget _buildReorderableList(BuildContext context) {
    return SliverReorderableList(
      itemExtent: 56,
      itemBuilder: (context, index) {
        final music = widget.songs[index];
        return _buildTrackRow(
          context,
          music,
          index,
          key: ValueKey(
            '${music.id}_${music.pages.isNotEmpty ? music.pages[0].cid : "0"}',
          ),
        );
      },
      itemCount: widget.songs.length,
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
    );
  }

  Widget _buildTrackRow(
    BuildContext context,
    Music music,
    int index, {
    Key? key,
  }) {
    return PlaylistTrackRow(
      key: key,
      music: music,
      index: index,
      isPlaying: _isCurrentPlaying(music),
      isLandscape: widget.isLandscape,
      selectionMode: _selectionMode,
      selected: _selectedKeys.contains(music.key),
      onSelectionToggle: () => _toggleSelection(music),
      onTap: () => widget.onSongTap(music),
      onRemoveFromPlaylist: widget.isEditable && widget.onRemove != null
          ? () => widget.onRemove?.call(music)
          : null,
    );
  }

  bool _isCurrentPlaying(Music music) {
    final current = widget.currentPlayingMusic;
    if (current == null) return false;
    return music.id == current.id &&
        (music.pages.isEmpty && current.pages.isEmpty ||
            music.pages.isNotEmpty &&
                current.pages.isNotEmpty &&
                music.pages[0].cid == current.pages[0].cid);
  }
}

/// Track row widget for playlist song list.
/// Shows index, title (with artist subtitle), duration (landscape only),
/// and heart icon.
class PlaylistTrackRow extends ConsumerStatefulWidget {
  final Music music;
  final int index;
  final bool isPlaying;
  final bool isLandscape;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onSelectionToggle;
  final VoidCallback? onRemoveFromPlaylist;

  const PlaylistTrackRow({
    super.key,
    required this.music,
    required this.index,
    this.isPlaying = false,
    this.isLandscape = false,
    this.selectionMode = false,
    this.selected = false,
    this.onTap,
    this.onSelectionToggle,
    this.onRemoveFromPlaylist,
  });

  @override
  ConsumerState<PlaylistTrackRow> createState() => _PlaylistTrackRowState();
}

class _PlaylistTrackRowState extends ConsumerState<PlaylistTrackRow> {
  bool _isHovered = false;

  /// 时长兜底链：总时长 → 首分P时长 → `--:--`（格式化统一走 [formatDuration]）。
  String _formatDuration(Music music) {
    if (music.duration != null) return formatDuration(music.duration!);
    if (music.pages.isNotEmpty) {
      return formatDuration(music.pages.first.durationValue);
    }
    return '--:--';
  }

  /// 把当前歌曲插到正在播放的曲目后面。
  Future<void> _playNext() async {
    final music = widget.music;
    try {
      await ref
          .read(playbackCommandsProvider.notifier)
          .playNextFromIndex(music);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加到下一首播放"${music.title}"'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('添加下一首播放失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;

    final row = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.selectionMode ? widget.onSelectionToggle : widget.onTap,
        child: AnimatedContainer(
          duration: BmMotion.medium,
          curve: Curves.easeOutCubic,
          height: 56,
          decoration: BoxDecoration(
            color: widget.selected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : (_isHovered ? palette.surfaceHover : Colors.transparent),
            border: Border(
              bottom: BorderSide(color: colorScheme.outline, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Index / 多选勾选
                SizedBox(
                  width: 32,
                  child: widget.selectionMode
                      ? Checkbox(
                          value: widget.selected,
                          onChanged: (_) => widget.onSelectionToggle?.call(),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        )
                      : Text(
                          '${widget.index + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.isPlaying
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            fontWeight: widget.isPlaying
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                // Title + artist subtitle
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.music.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.isPlaying
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.music.subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 竖屏空间有限，不显示时长，避免挤压歌曲标题/歌手信息
                if (widget.isLandscape) ...[
                  const SizedBox(width: 8),
                  // Duration
                  SizedBox(
                    width: 48,
                    child: Text(
                      _formatDuration(widget.music),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // 多选模式下收起行内操作，避免与勾选语义打架
                if (!widget.selectionMode) ...[
                  // 下一首播放
                  IconButton(
                    onPressed: widget.isPlaying ? null : _playNext,
                    icon: const Icon(Icons.playlist_play),
                    iconSize: 18,
                    color: colorScheme.onSurfaceVariant,
                    disabledColor: colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.35,
                    ),
                    tooltip: '下一首播放',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                  ),
                  const SizedBox(width: 2),
                  // 更多菜单
                  MusicMenuButton(
                    music: widget.music,
                    onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.selectionMode) return row;

    return ContextMenuWidget(
      menuProvider: (_) => buildMusicContextMenu(
        context: context,
        music: widget.music,
        playerCoordinator: ref.read(playerCoordinatorProvider),
        commands: ref.read(playlistCommandsProvider.notifier),
        onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
        ref: ref,
      ),
      child: row,
    );
  }
}
