import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/widgets/music_cover.dart';

/// 横屏右侧播放队列面板（设计稿 `.queue-drawer`）。
///
/// 只挂在内容区 Stack 里：`right: 0`、`top/bottom: 0`，宽 420，圆角 0。
/// 头部标题 + 曲目数 / 总时长，中部可拖动排序的行，底部提示与清空。
class LandscapeQueuePanel extends ConsumerWidget {
  const LandscapeQueuePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  /// 设计稿 `.queue-drawer`：行高 56、封面 36、行内间距 10。
  static const double _rowGap = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );
    final playlist = ref.watch(currentPlaylistProvider);
    final currentIndex = ref.watch(currentIndexProvider) ?? -1;
    final isPlaying = ref.watch(playerStateProvider) is PlayerPlaying;
    final total = playlist.fold(
      Duration.zero,
      (sum, music) => sum + _durationOf(music),
    );

    return SizedBox(
      width: BmTokens.queuePanelWidth,
      child: BmChromeSurface(
        edges: const <BmChromeEdge>{BmChromeEdge.left},
        blur: blur,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            BmTokens.s5,
            18,
            BmTokens.s5,
            BmTokens.s4,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: BmTokens.s3),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '播放队列',
                            style: type.title.copyWith(
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: BmTokens.s1),
                          Text(
                            _kicker(playlist, total),
                            style: type.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    BmIconButton(
                      icon: Icons.close_rounded,
                      tooltip: '关闭',
                      size: BmIconButtonSize.xl,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: playlist.isEmpty
                    ? const BmEmptyState(
                        compact: true,
                        icon: Icons.queue_music_rounded,
                        title: '队列是空的',
                        message: '从任意列表点一首歌开始播放',
                      )
                    : _buildList(
                        context,
                        ref,
                        playlist,
                        currentIndex,
                        isPlaying,
                      ),
              ),
              Container(
                padding: const EdgeInsets.only(top: BmTokens.s2 + 2),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '拖动可调整顺序',
                        style: type.micro.copyWith(color: colors.textTertiary),
                      ),
                    ),
                    TextButton(
                      onPressed: playlist.isEmpty
                          ? null
                          : () => _confirmClear(context, ref),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        textStyle: type.micro,
                        padding: const EdgeInsets.symmetric(
                          horizontal: BmTokens.s2,
                        ),
                        minimumSize: const Size(0, BmTokens.touchDesktop),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('清空队列'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<Music> playlist,
    int currentIndex,
    bool isPlaying,
  ) {
    // 重复曲目用「出现序号」给稳定 key，排序时不会撞车。
    final itemKeys = <String>[];
    final occurrences = <String, int>{};
    for (final music in playlist) {
      final base = '${music.id}_${music.cid}';
      final occurrence = occurrences.update(
        base,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      itemKeys.add('$base-$occurrence');
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 6),
      itemCount: playlist.length,
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        ref
            .read(playlistCommandsProvider.notifier)
            .moveInPlaylist(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final music = playlist[index];
        return _QueueRow(
          key: ValueKey(itemKeys[index]),
          music: music,
          index: index,
          isCurrent: index == currentIndex,
          isPlaying: index == currentIndex && isPlaying,
          onTap: () =>
              ref.read(playbackCommandsProvider.notifier).playAtIndex(index),
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showBmDialog<bool>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: '清空播放队列',
        content: const Text('清空后当前歌曲会继续播放，队列将变为空。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '清空',
              style: TextStyle(color: BmColors.of(dialogContext).danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(playbackCommandsProvider.notifier).clearPlaylist();
    }
  }

  String _kicker(List<Music> playlist, Duration total) {
    if (playlist.isEmpty) return 'QUEUE · 队列为空';
    return 'QUEUE · ${playlist.length} 首 · ${_totalLabel(total)}';
  }

  String _totalLabel(Duration total) {
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);
    if (hours > 0) return '$hours 小时 ${minutes.toString().padLeft(2, '0')} 分';
    return '${total.inMinutes} 分钟';
  }

  static Duration _durationOf(Music music) {
    final duration = music.duration;
    if (duration != null) return duration;
    if (music.pages.isNotEmpty) return music.pages.first.durationValue;
    return Duration.zero;
  }
}

/// 队列行：封面 36 / 标题 + UP 主 / 当前项跳动条 / 时长 / 拖拽手柄。
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.music,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final Music music;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  static const double _coverSize = 36;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return BmPressable(
      onTap: onTap,
      selected: isCurrent,
      selectedColor: colors.accentSoft,
      borderRadius: BorderRadius.zero,
      semanticLabel: '${music.title}，${music.artist.displayName}',
      child: Container(
        height: BmTokens.trackRowCompact,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.hairline,
              width: BmTokens.hairlineWidth,
            ),
          ),
        ),
        child: Row(
          children: [
            MusicCover(music: music, size: _coverSize, radius: BmTokens.r9),
            const SizedBox(width: LandscapeQueuePanel._rowGap),
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
                      color: isCurrent ? colors.accentDeep : colors.textPrimary,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCurrent
                        ? '${music.artist.displayName} · 正在播放'
                        : music.artist.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(
                      color: isCurrent
                          ? colors.accentDeep
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: BmTokens.s2),
              _PlayingBars(active: isPlaying),
            ],
            const SizedBox(width: BmTokens.s2),
            Text(
              _durationLabel(music),
              style: BmTypography.numeric(type.micro)
                  .copyWith(color: colors.textTertiary),
            ),
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.s1,
                    vertical: BmTokens.s3,
                  ),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: BmTokens.iconMenu,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _durationLabel(Music music) {
    final duration = music.duration;
    if (duration != null) return formatDuration(duration);
    if (music.pages.isNotEmpty) {
      return formatDuration(music.pages.first.durationValue);
    }
    return '--:--';
  }
}

/// 当前曲目的三根跳动条（设计稿 `.playing-bars`）。
class _PlayingBars extends StatefulWidget {
  const _PlayingBars({required this.active});

  final bool active;

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  /// 设计稿三根条的高度。
  static const List<double> _heights = <double>[6, 11, 8];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BmMotion.xlarge,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
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
    return SizedBox(
      width: 12,
      height: _heights.reduce((a, b) => a > b ? a : b),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _heights.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Transform.scale(
                  scaleY: widget.active
                      ? 0.55 + 0.45 * ((_controller.value + i * 0.2) % 1.0)
                      : 0.7,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 2.5,
                    height: _heights[i],
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BmTokens.rPillAll,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
