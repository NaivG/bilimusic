import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/logic/offline_cache_index.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';
import 'package:bilimusic/shared/widgets/music_menu_button.dart';

/// 歌单曲目表：白卡 + 58 行（横屏 56）。
///
/// 表头「曲目 / N 首 · 总时长」、当前行 `accentSoft` 底 + 跳动条、
/// 行尾更多菜单；支持多选（批量删除 / 批量缓存）与拖拽排序。
///
/// 曲目数据由调用方一次性给全（全量在内存里），这里只负责把整份列表交给
/// sliver 按滚动视口懒构建：滚到哪构建到哪，滚出视口的行随之回收。
/// 卡片装饰取值与 `BmCard` 一致，但走 `DecoratedSliver` 以保留列表懒构建
/// 与 `SliverReorderableList`。
class PlaylistSongList extends ConsumerStatefulWidget {
  final List<Music> songs;
  final Music? currentPlayingMusic;
  final Function(Music) onSongTap;
  final Function(int, int)? onReorder;
  final Function(Music)? onRemove;

  /// 批量删除回调，返回是否实际删除。
  ///
  /// 与 [onCacheMany] 任一非空时表头显示「多选」入口。
  final Future<bool> Function(List<Music>)? onRemoveMany;

  /// 批量缓存回调：把多选中的曲目交给离线缓存链路。
  ///
  /// 传入的是选中曲目（按曲目表顺序），已缓存/音质足够的跳过逻辑由回调方
  /// 的批量下载流程负责；回调内部通常展示进度对话框，返回时缓存已结束。
  final Future<void> Function(List<Music>)? onCacheMany;
  final bool isEditable;
  final bool isLandscape;

  /// 白卡左右外边距；为 null 时取 [BmTokens.pageInset]。
  final double? horizontalInset;

  const PlaylistSongList({
    super.key,
    required this.songs,
    this.currentPlayingMusic,
    required this.onSongTap,
    this.onReorder,
    this.onRemove,
    this.onRemoveMany,
    this.onCacheMany,
    this.isEditable = false,
    this.isLandscape = false,
    this.horizontalInset,
  });

  @override
  ConsumerState<PlaylistSongList> createState() => _PlaylistSongListState();
}

class _PlaylistSongListState extends ConsumerState<PlaylistSongList> {
  bool _selectionMode = false;

  /// 当前进行中的批量操作：非空期间禁用工具栏，避免重复触发。
  _BatchAction? _busyAction;

  final Set<String> _selectedKeys = <String>{};

  List<Music> get _selectedSongs =>
      widget.songs.where((music) => _selectedKeys.contains(music.key)).toList();

  _TrackMetrics get _metrics => _TrackMetrics.of(widget.isLandscape);

  bool get _isReorderable =>
      widget.isEditable && widget.onReorder != null && !_selectionMode;

  bool get _isBusy => _busyAction != null;

  /// 有任一批量操作才需要多选入口；只读列表（如歌手投稿）保持原样。
  bool get _hasBatchActions =>
      widget.onRemoveMany != null || widget.onCacheMany != null;

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
    if (songs.isEmpty || onRemoveMany == null || _isBusy) return;

    setState(() => _busyAction = _BatchAction.delete);
    var removed = false;
    try {
      removed = await onRemoveMany(songs);
    } catch (_) {
      // 错误提示由回调方负责，这里只恢复按钮状态。
    }
    if (!mounted) return;
    setState(() {
      _busyAction = null;
      if (removed) {
        _selectionMode = false;
        _selectedKeys.clear();
      }
    });
  }

  /// 把选中的曲目交给离线缓存流程（已缓存的由批量链路跳过）。
  ///
  /// 缓存结束后保留多选态：失败/跳过的曲目可以立刻再操作一次。
  Future<void> _cacheSelected() async {
    final songs = _selectedSongs;
    final onCacheMany = widget.onCacheMany;
    if (songs.isEmpty || onCacheMany == null || _isBusy) return;

    setState(() => _busyAction = _BatchAction.cache);
    try {
      await onCacheMany(songs);
    } catch (_) {
      // 错误提示由回调方负责，这里只恢复按钮状态。
    }
    if (!mounted) return;
    setState(() => _busyAction = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final horizontal = widget.horizontalInset ?? BmTokens.pageInset;

    if (widget.songs.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: horizontal),
        sliver: const SliverFillRemaining(
          hasScrollBody: false,
          child: BmEmptyState(
            icon: Icons.music_off_rounded,
            title: '歌单为空',
            message: '快去添加喜欢的音乐吧',
          ),
        ),
      );
    }

    // 全量曲目直接进滚动容器：行由 sliver 按视口懒构建，不做行数截断。
    final count = widget.songs.length;
    // 「已缓存」标记只在多选态用得上：普通浏览时不订阅离线表。
    final cacheIndex = _selectionMode
        ? ref.watch(offlineCacheIndexProvider)
        : null;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: const BorderRadius.all(
            Radius.circular(BmTokens.mediaCardRadius),
          ),
          border: Border.all(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.shadow,
              blurRadius: BmTokens.s6,
              offset: const Offset(0, BmTokens.s1),
            ),
          ],
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            if (_isReorderable)
              _buildReorderableList(context, count, cacheIndex)
            else
              _buildSliverList(context, count, cacheIndex),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      height: BmTokens.rowCompact,
      padding: EdgeInsets.symmetric(horizontal: _metrics.inset),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
      ),
      child: _selectionMode
          ? _buildSelectionHeader(context)
          : _buildColumnHeader(context),
    );
  }

  Widget _buildColumnHeader(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final totalSeconds = widget.songs.fold<int>(
      0,
      (sum, music) => sum + _secondsOf(music),
    );
    final total = formatDuration(Duration(seconds: totalSeconds));

    return Row(
      children: [
        Text(
          '曲目',
          style: type.label.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        // 统计文本吃掉中间全部空间：窄屏 / 大字号下宁可省略，
        // 也不把「多选」入口挤出可视区。
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${widget.songs.length} 首 · $total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BmTypography.numeric(
                type.micro.copyWith(color: colors.textTertiary),
              ),
            ),
          ),
        ),
        if (_hasBatchActions) ...[
          const SizedBox(width: BmTokens.s2),
          _HeaderAction(
            icon: Icons.checklist_rounded,
            label: '多选',
            onTap: _enterSelectionMode,
          ),
        ],
      ],
    );
  }

  Widget _buildSelectionHeader(BuildContext context) {
    // 完整标签（全选 / 缓存 / 删除 + 已选计数）在默认字号下约需 340 宽；
    // 窄屏或大字号时放不下，就退化成图标按钮，把宽度留给「已选 N 首」，
    // 同时保证 320 宽 + 系统大字号下也不会横向溢出。
    final labelSize = context.bmType.label.fontSize ?? 13;
    final textScale =
        MediaQuery.textScalerOf(context).scale(labelSize) / labelSize;
    final hasDelete = widget.onRemoveMany != null;
    final fullWidth = (hasDelete ? 340.0 : 270.0) * textScale;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < fullWidth) {
          return _buildCompactSelectionHeader(context);
        }
        return _buildLabeledSelectionHeader(context);
      },
    );
  }

  Widget _buildLabeledSelectionHeader(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final count = _selectedSongs.length;
    final allSelected = count == widget.songs.length;

    return Row(
      children: [
        // 标题可压缩：窄屏下让位给操作按钮，不撑出横向溢出。
        Expanded(
          child: Text(
            '已选 $count 首',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.label.copyWith(
              color: colors.accentDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: _isBusy ? null : _toggleSelectAll,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, BmTokens.controlSm),
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: colors.textSecondary,
          ),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        if (widget.onCacheMany != null) ...[
          const SizedBox(width: BmTokens.s1),
          TextButton.icon(
            onPressed: count == 0 || _isBusy ? null : _cacheSelected,
            icon: _busyAction == _BatchAction.cache
                ? SizedBox.square(
                    dimension: BmTokens.iconInline,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accentDeep,
                    ),
                  )
                : const Icon(
                    Icons.download_outlined,
                    size: BmTokens.iconInline,
                  ),
            label: const Text('缓存'),
            style: TextButton.styleFrom(
              foregroundColor: colors.accentDeep,
              minimumSize: const Size(0, BmTokens.controlSm),
              padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        if (widget.onRemoveMany != null) ...[
          const SizedBox(width: BmTokens.s1),
          FilledButton.icon(
            onPressed: count == 0 || _isBusy ? null : _deleteSelected,
            icon: _busyAction == _BatchAction.delete
                ? SizedBox.square(
                    dimension: BmTokens.iconInline,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onDanger,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline_rounded,
                    size: BmTokens.iconInline,
                  ),
            label: const Text('删除'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: colors.onDanger,
              disabledBackgroundColor: colors.danger.withValues(
                alpha: BmAlpha.disabled,
              ),
              disabledForegroundColor: colors.onDanger.withValues(
                alpha: BmAlpha.disabled,
              ),
              minimumSize: const Size(0, BmTokens.controlSm),
              padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
            ),
          ),
        ],
        const SizedBox(width: BmTokens.s1),
        _SelectionIconAction(
          icon: Icons.close_rounded,
          label: '退出多选',
          color: colors.textSecondary,
          onTap: _isBusy ? null : _exitSelectionMode,
        ),
      ],
    );
  }

  /// 窄屏 / 大字号下的紧凑工具栏：图标按钮固定 28 宽，不随字号膨胀。
  Widget _buildCompactSelectionHeader(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final count = _selectedSongs.length;
    final allSelected = count == widget.songs.length;

    return Row(
      children: [
        Expanded(
          child: Text(
            '已选 $count 首',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.label.copyWith(
              color: colors.accentDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _SelectionIconAction(
          // 用方框勾选态表达「全部选中」，和文字版的 全选 / 取消全选 对应；
          // select_all / deselect 两个字形在 16px 下几乎分不出来，不采用。
          icon: allSelected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          label: allSelected ? '取消全选' : '全选',
          color: colors.textSecondary,
          onTap: _isBusy ? null : _toggleSelectAll,
        ),
        if (widget.onCacheMany != null) ...[
          const SizedBox(width: BmTokens.s1),
          _SelectionIconAction(
            icon: Icons.download_outlined,
            label: count > 0 ? '缓存选中的 $count 首' : '缓存',
            color: colors.accentDeep,
            busy: _busyAction == _BatchAction.cache,
            onTap: count == 0 || _isBusy ? null : _cacheSelected,
          ),
        ],
        if (widget.onRemoveMany != null) ...[
          const SizedBox(width: BmTokens.s1),
          _SelectionIconAction(
            icon: Icons.delete_outline_rounded,
            label: count > 0 ? '删除选中的 $count 首' : '删除',
            color: colors.danger,
            busy: _busyAction == _BatchAction.delete,
            onTap: count == 0 || _isBusy ? null : _deleteSelected,
          ),
        ],
        const SizedBox(width: BmTokens.s1),
        _SelectionIconAction(
          icon: Icons.close_rounded,
          label: '退出多选',
          color: colors.textSecondary,
          onTap: _isBusy ? null : _exitSelectionMode,
        ),
      ],
    );
  }

  Widget _buildSliverList(
    BuildContext context,
    int count,
    OfflineCacheIndex? cacheIndex,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return _buildTrackRow(
          context,
          index,
          cacheIndex: cacheIndex,
          showDivider: index != count - 1,
        );
      }, childCount: count),
    );
  }

  Widget _buildReorderableList(
    BuildContext context,
    int count,
    OfflineCacheIndex? cacheIndex,
  ) {
    return SliverReorderableList(
      itemExtent: _metrics.height,
      itemBuilder: (context, index) {
        final music = widget.songs[index];
        return _buildTrackRow(
          context,
          index,
          cacheIndex: cacheIndex,
          key: ValueKey(
            '${music.id}_${music.pages.isNotEmpty ? music.pages[0].cid : "0"}',
          ),
          showDivider: index != count - 1,
        );
      },
      itemCount: count,
      onReorderItem: (oldIndex, newIndex) {
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
    int index, {
    required OfflineCacheIndex? cacheIndex,
    Key? key,
    required bool showDivider,
  }) {
    final music = widget.songs[index];
    return PlaylistTrackRow(
      key: key,
      music: music,
      index: index,
      isPlaying: _isCurrentPlaying(music),
      isLandscape: widget.isLandscape,
      selectionMode: _selectionMode,
      selected: _selectedKeys.contains(music.key),
      cached: cacheIndex?.contains(music) ?? false,
      showDivider: showDivider,
      onTap: () => widget.onSongTap(music),
      onSelectionToggle: () => _toggleSelection(music),
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

/// 多选工具栏进行中的批量操作：决定禁用态与哪个按钮显示进度圈。
enum _BatchAction { cache, delete }

/// 曲目行几何：竖屏 `20 / 36 / 1fr / 38 / 20`，横屏 `26 / 40 / 1fr / 50 / 24`。
class _TrackMetrics {
  const _TrackMetrics({
    required this.height,
    required this.inset,
    required this.gap,
    required this.index,
    required this.cover,
    required this.duration,
    required this.more,
  });

  final double height;
  final double inset;
  final double gap;
  final double index;
  final double cover;
  final double duration;
  final double more;

  static const _TrackMetrics portrait = _TrackMetrics(
    height: BmTokens.trackRow,
    inset: 12,
    gap: 9,
    index: 20,
    cover: 36,
    duration: 38,
    more: 20,
  );

  static const _TrackMetrics landscape = _TrackMetrics(
    height: BmTokens.trackRowCompact,
    inset: 16,
    gap: 12,
    index: 26,
    cover: 40,
    duration: 50,
    more: 24,
  );

  static _TrackMetrics of(bool isLandscape) =>
      isLandscape ? landscape : portrait;

  /// 分隔线起点：封面列左缘。
  double get dividerInset => inset + index + gap;
}

/// 曲目行：序号/跳动条 + 封面 + 标题副标题 + 时长 + 更多。
///
/// 多选态隐藏「更多」，行尾同宽的位置改显示「已缓存」标记。
class PlaylistTrackRow extends ConsumerWidget {
  const PlaylistTrackRow({
    super.key,
    required this.music,
    required this.index,
    this.isPlaying = false,
    this.isLandscape = false,
    this.selectionMode = false,
    this.selected = false,
    this.cached = false,
    this.showDivider = false,
    this.onTap,
    this.onSelectionToggle,
    this.onRemoveFromPlaylist,
  });

  final Music music;
  final int index;
  final bool isPlaying;
  final bool isLandscape;
  final bool selectionMode;
  final bool selected;

  /// 本地已有离线缓存（多选态在行尾显示标记，批量缓存时会跳过）。
  final bool cached;

  /// 是否画行间 0.5px 分隔线（最后一行不画）。
  final bool showDivider;

  final VoidCallback? onTap;
  final VoidCallback? onSelectionToggle;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final metrics = _TrackMetrics.of(isLandscape);

    final row = SizedBox(
      height: metrics.height,
      child: Stack(
        children: [
          if (isPlaying)
            Positioned.fill(child: ColoredBox(color: colors.accentSoft)),
          Positioned.fill(
            child: BmPressable(
              onTap: selectionMode ? onSelectionToggle : onTap,
              selected: selected,
              selectedColor: colors.accentSoft,
              borderRadius: BorderRadius.zero,
              semanticLabel: cached
                  ? '${music.title}，${music.subtitleText}，已缓存'
                  : '${music.title}，${music.subtitleText}',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.inset),
                child: Row(
                  children: [
                    SizedBox(
                      width: metrics.index,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _buildIndexCell(colors, type),
                      ),
                    ),
                    SizedBox(width: metrics.gap),
                    ClipRRect(
                      borderRadius: BmTokens.albumArtRadius,
                      child: SizedBox.square(
                        dimension: metrics.cover,
                        child: BmArtImage(url: music.safeCoverUrl),
                      ),
                    ),
                    SizedBox(width: metrics.gap),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            music.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.label.copyWith(
                              color: isPlaying
                                  ? colors.accentDeep
                                  : colors.textPrimary,
                              fontWeight: isPlaying
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          if (music.subtitleText.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              music.subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.micro.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: metrics.gap),
                    SizedBox(
                      width: metrics.duration,
                      child: Text(
                        _durationText(music),
                        textAlign: TextAlign.right,
                        style: BmTypography.numeric(
                          type.micro.copyWith(color: colors.textTertiary),
                        ),
                      ),
                    ),
                    if (!selectionMode) ...[
                      SizedBox(width: metrics.gap),
                      SizedBox.square(
                        dimension: metrics.more,
                        child: MusicMenuButton(
                          music: music,
                          onRemoveFromPlaylist: onRemoveFromPlaylist,
                        ),
                      ),
                    ] else ...[
                      // 多选态替掉「更多」的位置：保留相同时长列宽，已缓存
                      // 曲目在行尾标一下，免得缓存完看到「跳过 N 首」发懵。
                      SizedBox(width: metrics.gap),
                      SizedBox.square(
                        dimension: metrics.more,
                        child: cached
                            ? Icon(
                                Icons.download_done_rounded,
                                size: BmTokens.iconMenu,
                                color: colors.textSecondary,
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (showDivider)
            Positioned(
              left: metrics.dividerInset,
              right: metrics.inset,
              bottom: 0,
              child: SizedBox(
                height: BmTokens.hairlineWidth,
                child: ColoredBox(color: colors.hairline),
              ),
            ),
        ],
      ),
    );

    if (selectionMode) return row;

    return AppContextMenu(
      menuProvider: (_) => buildMusicContextMenu(
        context: context,
        music: music,
        playerCoordinator: ref.read(playerCoordinatorProvider),
        commands: ref.read(playlistCommandsProvider.notifier),
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        ref: ref,
      ),
      child: row,
    );
  }

  Widget _buildIndexCell(BmColors colors, BmTypographySet type) {
    if (selectionMode) {
      return _SelectionDot(selected: selected);
    }
    if (isPlaying) {
      return const _PlayingBars();
    }
    return Text(
      '${index + 1}'.padLeft(2, '0'),
      textAlign: TextAlign.right,
      style: BmTypography.numeric(
        type.micro.copyWith(color: colors.textTertiary),
      ),
    );
  }

  String _durationText(Music music) {
    if (music.duration != null) return formatDuration(music.duration!);
    if (music.pages.isNotEmpty) {
      return formatDuration(music.pages.first.durationValue);
    }
    return '--:--';
  }
}

/// 多选工具栏的图标按钮：28 见方，带 Tooltip 与语义标签。
///
/// 固定尺寸，不随字号放大 —— 大字号下工具栏宽度仍可控。
class _SelectionIconAction extends StatelessWidget {
  const _SelectionIconAction({
    required this.icon,
    required this.label,
    required this.color,
    this.busy = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// 该操作正在进行中：图标换成进度圈。
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tint = enabled ? color : color.withValues(alpha: BmAlpha.disabled);

    return Tooltip(
      message: label,
      child: BmPressable(
        onTap: onTap,
        borderRadius: BmTokens.r10All,
        semanticLabel: label,
        child: SizedBox.square(
          dimension: BmTokens.controlSm,
          child: Center(
            child: busy
                ? SizedBox.square(
                    dimension: BmTokens.iconInline,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, size: BmTokens.iconMenu, color: tint),
          ),
        ),
      ),
    );
  }
}

/// 多选勾选圆点。
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      width: BmTokens.iconMenu,
      height: BmTokens.iconMenu,
      decoration: BoxDecoration(
        color: selected ? colors.accent : null,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(
                color: colors.lineStrong,
                width: BmTokens.hairlineWidth,
              ),
      ),
      child: selected
          ? Icon(
              Icons.check_rounded,
              size: BmTokens.iconInline,
              color: colors.onAccent,
            )
          : null,
    );
  }
}

/// 当前曲目序号位的三根跳动条（高 8 / 12 / 6，错相循环）。
class _PlayingBars extends StatefulWidget {
  const _PlayingBars();

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  static const List<double> _baseHeights = <double>[8, 12, 6];
  static const List<double> _phaseOffsets = <double>[0, 0.33, 0.66];
  static const double _barWidth = 2.5;
  static const double _barGap = 2;
  static const double _maxHeight = 12;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BmMotion.sheetMax,
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final reduce = reduceMotionOf(context);

    return SizedBox(
      height: _maxHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _baseHeights.length; i++) ...[
                if (i > 0) const SizedBox(width: _barGap),
                Container(
                  width: _barWidth,
                  height: _barHeight(i, reduce),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BmTokens.rPillAll,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  double _barHeight(int index, bool reduce) {
    if (reduce) return _baseHeights[index];
    final phase = (_controller.value + _phaseOffsets[index]) % 1.0;
    final wave = 0.5 - 0.5 * math.cos(phase * 2 * math.pi);
    return _baseHeights[index] * (0.55 + 0.45 * wave);
  }
}

/// 表头右侧的小按钮（多选入口）。
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r10All,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: BmTokens.iconInline, color: colors.textSecondary),
            const SizedBox(width: BmTokens.s1),
            Text(
              label,
              style: type.micro.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

int _secondsOf(Music music) {
  if (music.duration != null) return music.duration!.inSeconds;
  if (music.pages.isNotEmpty) return music.pages.first.durationValue.inSeconds;
  return 0;
}
