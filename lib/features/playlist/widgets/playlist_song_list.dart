import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
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
/// 行尾更多菜单；保留多选、拖拽排序与「查看全部」折叠。
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
  /// 非空时表头显示「多选」入口。
  final Future<bool> Function(List<Music>)? onRemoveMany;
  final bool isEditable;
  final bool isLandscape;

  /// 折叠预览行数；null 表示不折叠（不出现「查看全部」）。
  final int? previewLimit;

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
    this.isEditable = false,
    this.isLandscape = false,
    this.previewLimit,
    this.horizontalInset,
  });

  @override
  ConsumerState<PlaylistSongList> createState() => _PlaylistSongListState();
}

class _PlaylistSongListState extends ConsumerState<PlaylistSongList> {
  bool _selectionMode = false;
  bool _isDeleting = false;
  bool _expanded = false;
  final Set<String> _selectedKeys = <String>{};

  List<Music> get _selectedSongs =>
      widget.songs.where((music) => _selectedKeys.contains(music.key)).toList();

  _TrackMetrics get _metrics => _TrackMetrics.of(widget.isLandscape);

  bool get _isReorderable =>
      widget.isEditable && widget.onReorder != null && !_selectionMode;

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

    final limit = widget.previewLimit;
    final visibleCount = _expanded || limit == null
        ? widget.songs.length
        : math.min(limit, widget.songs.length);
    final showFooter =
        limit != null && !_expanded && widget.songs.length > limit;

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
              _buildReorderableList(context, visibleCount)
            else
              _buildSliverList(context, visibleCount),
            if (showFooter) SliverToBoxAdapter(child: _buildFooter(context)),
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
        const Spacer(),
        Text(
          '${widget.songs.length} 首 · $total',
          style: BmTypography.numeric(
            type.micro.copyWith(color: colors.textTertiary),
          ),
        ),
        if (widget.onRemoveMany != null) ...[
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
    final colors = context.bmColors;
    final type = context.bmType;
    final count = _selectedSongs.length;
    final allSelected = count == widget.songs.length;

    return Row(
      children: [
        Text(
          '已选 $count 首',
          style: type.label.copyWith(
            color: colors.accentDeep,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _isDeleting ? null : _toggleSelectAll,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, BmTokens.controlSm),
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: colors.textSecondary,
          ),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        const SizedBox(width: BmTokens.s1),
        FilledButton.icon(
          onPressed: count == 0 || _isDeleting ? null : _deleteSelected,
          icon: _isDeleting
              ? SizedBox.square(
                  dimension: BmTokens.iconInline,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onDanger,
                  ),
                )
              : const Icon(Icons.delete_outline_rounded),
          label: Text(count > 0 ? '删除 ($count)' : '删除'),
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
        const SizedBox(width: BmTokens.s1),
        BmPressable(
          onTap: _isDeleting ? null : _exitSelectionMode,
          borderRadius: BmTokens.r10All,
          semanticLabel: '退出多选',
          child: SizedBox.square(
            dimension: BmTokens.controlSm,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: BmTokens.iconMenu,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverList(BuildContext context, int count) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return _buildTrackRow(context, index, showDivider: index != count - 1);
      }, childCount: count),
    );
  }

  Widget _buildReorderableList(BuildContext context, int count) {
    return SliverReorderableList(
      itemExtent: _metrics.height,
      itemBuilder: (context, index) {
        final music = widget.songs[index];
        return _buildTrackRow(
          context,
          index,
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
      showDivider: showDivider,
      onTap: () => widget.onSongTap(music),
      onSelectionToggle: () => _toggleSelection(music),
      onRemoveFromPlaylist: widget.isEditable && widget.onRemove != null
          ? () => widget.onRemove?.call(music)
          : null,
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final label = '查看全部 ${widget.songs.length} 首';

    return Container(
      height: BmTokens.controlLg,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
      ),
      child: BmPressable(
        onTap: () => setState(() => _expanded = true),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(BmTokens.mediaCardRadius),
        ),
        semanticLabel: label,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: type.micro.copyWith(
                  color: colors.accentDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: BmTokens.s1),
              Icon(
                Icons.chevron_right_rounded,
                size: BmTokens.iconInline,
                color: colors.accentDeep,
              ),
            ],
          ),
        ),
      ),
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
class PlaylistTrackRow extends ConsumerWidget {
  const PlaylistTrackRow({
    super.key,
    required this.music,
    required this.index,
    this.isPlaying = false,
    this.isLandscape = false,
    this.selectionMode = false,
    this.selected = false,
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
              semanticLabel: '${music.title}，${music.subtitleText}',
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
