import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/pip/pip_service.dart';
import 'package:bilimusic/features/player/widgets/crossfade_indicator.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/utils/animations.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/widgets/music_cover.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端画中画覆盖层。
///
/// 布局：左侧封面顶满窗口高度（正方形，切歌时旧封面左滑淡出、新封面自右滑入），
/// 右侧控制区自上而下为歌曲信息、可拖动进度条（带时间显示）与传输控件。
class PipOverlay extends ConsumerWidget {
  const PipOverlay({super.key});

  void _togglePlay(PlayerState state, WidgetRef ref) {
    final commands = ref.read(playbackCommandsProvider.notifier);
    if (state is PlayerPlaying) {
      commands.pause();
    } else if (state is PlayerPaused || state is PlayerCompleted) {
      commands.resume();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(playerStateProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Stack(
          children: [
            _buildBackground(context),
            // 空白区域拖动窗口；交互控件位于上层，各自消费手势
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => windowManager.startDragging(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PipCoverPanel(music: currentMusic),
                  Expanded(
                    child: _PipControlPanel(
                      music: currentMusic,
                      playerState: playerState,
                      onTogglePlay: () => _togglePlay(playerState, ref),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    final palette = context.appPalette;
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: AppTokens.overlayBlurSigma,
        sigmaY: AppTokens.overlayBlurSigma,
      ),
      child: Container(color: palette.surfaceOverlay),
    );
  }
}

/// 左侧封面面板：顶满窗口高度的正方形。
///
/// 切歌动画：旧封面向左滑出 + 淡出，新封面自右滑入 + 淡入。
/// 不用 AnimatedSwitcher——两个子项需要相反方向的位移，
/// 用单个 AnimationController 显式编排入场/出场两份动画。
class _PipCoverPanel extends StatefulWidget {
  final Music? music;

  const _PipCoverPanel({required this.music});

  @override
  State<_PipCoverPanel> createState() => _PipCoverPanelState();
}

class _PipCoverPanelState extends State<_PipCoverPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTokens.layoutDuration,
  );

  // 入场：自右滑入 + 淡入
  late final Animation<Offset> _inSlide = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  late final Animation<double> _inFade = Tween<double>(begin: 0, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.7, curve: Curves.easeOut),
        ),
      );

  // 出场：向左滑出 + 淡出
  late final Animation<Offset> _outSlide = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-1, 0),
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  late final Animation<double> _outFade = Tween<double>(begin: 1, end: 0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.3, 1, curve: Curves.easeIn),
        ),
      );

  Music? _current;
  Music? _outgoing;

  @override
  void initState() {
    super.initState();
    _current = widget.music;
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _outgoing != null) {
        setState(() => _outgoing = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PipCoverPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // key 含 bvid + cid，是队列域的唯一标识
    if (oldWidget.music?.key != widget.music?.key) {
      setState(() {
        _outgoing = _current;
        _current = widget.music;
      });
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 正方形边长跟随窗口高度
        final side = constraints.maxHeight;
        final currentCover = MusicCover(music: _current, size: side);
        final outgoingCover = _outgoing == null
            ? null
            : MusicCover(music: _outgoing, size: side);

        return SizedBox(
          // 钉死正方形边长：Row 给非 flex 子项的主轴宽度是无穷大，
          // 而「只有 Positioned 子项的 Stack」会取 constraints.biggest，
          // 不钉住会撑出无穷宽直接崩溃
          width: side,
          height: side,
          child: ClipRect(
            child: Stack(
              children: [
                if (outgoingCover != null) ...[
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: _outFade,
                      child: SlideTransition(
                        position: _outSlide,
                        child: outgoingCover,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: _inFade,
                      child: SlideTransition(
                        position: _inSlide,
                        child: currentCover,
                      ),
                    ),
                  ),
                ] else
                  // 无动画期直接平铺，避免首帧停留在 opacity 0
                  Positioned.fill(child: currentCover),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 右侧控制面板：歌曲信息 / 进度条 / 传输控件
class _PipControlPanel extends ConsumerWidget {
  final Music? music;
  final PlayerState playerState;
  final VoidCallback onTogglePlay;

  const _PipControlPanel({
    required this.music,
    required this.playerState,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurfaceVariant;
    final hasMusic = music != null;
    final isPlaying = playerState is PlayerPlaying;
    final commands = ref.read(playbackCommandsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: _SongInfo(
                  music: music,
                  playerState: playerState,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
              _PipIconButton(
                icon: Icons.close_rounded,
                iconSize: 16,
                iconColor: textSecondary,
                tooltip: '退出小窗',
                onTap: () => PipService().exitPipMode(),
              ),
            ],
          ),
          _PipSeekBar(music: music),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PipIconButton(
                icon: Icons.skip_previous_rounded,
                iconSize: 24,
                iconColor: textPrimary,
                tooltip: '上一首',
                onTap: hasMusic ? () => commands.playPrevious() : null,
              ),
              const SizedBox(width: 18),
              _PipPlayButton(
                isPlaying: isPlaying,
                enabled: hasMusic,
                tooltip: isPlaying ? '暂停' : '播放',
                onTap: onTogglePlay,
              ),
              const SizedBox(width: 18),
              _PipIconButton(
                icon: Icons.skip_next_rounded,
                iconSize: 24,
                iconColor: textPrimary,
                tooltip: '下一首',
                onTap: hasMusic ? () => commands.playNext() : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 歌名 + 歌手（crossfade 期间歌手行切换为过渡指示器）
class _SongInfo extends StatelessWidget {
  final Music? music;
  final PlayerState playerState;
  final Color textPrimary;
  final Color textSecondary;

  const _SongInfo({
    required this.music,
    required this.playerState,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final fading = isCrossfading(playerState);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          music?.title ?? 'Not Playing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (music != null) ...[
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: switcherFadeTransition,
            child: fading
                ? const CrossfadeIndicator()
                : Text(
                    music!.artist,
                    key: const ValueKey('artist'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textSecondary, fontSize: 11.5),
                  ),
          ),
        ],
      ],
    );
  }
}

/// 小窗圆形图标按钮（带悬停底色）
class _PipIconButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  const _PipIconButton({
    required this.icon,
    required this.iconSize,
    required this.iconColor,
    required this.tooltip,
    this.onTap,
  });

  @override
  State<_PipIconButton> createState() => _PipIconButtonState();
}

class _PipIconButtonState extends State<_PipIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTokens.microDuration,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled && _hover
                ? widget.iconColor.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: enabled
                ? widget.iconColor
                : widget.iconColor.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
    return Tooltip(message: widget.tooltip, child: button);
  }
}

/// 播放/暂停按钮：实心主色圆 + 悬停微缩放
class _PipPlayButton extends StatefulWidget {
  final bool isPlaying;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  const _PipPlayButton({
    required this.isPlaying,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_PipPlayButton> createState() => _PipPlayButtonState();
}

class _PipPlayButtonState extends State<_PipPlayButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = widget.enabled
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.10);
    final iconColor = widget.enabled
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedScale(
            scale: _hover && widget.enabled ? 1.06 : 1.0,
            duration: AppTokens.microDuration,
            curve: AppTokens.standardEasing,
            child: AnimatedContainer(
              duration: AppTokens.microDuration,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background,
              ),
              child: Icon(
                widget.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 24,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 可拖动进度条 + 时间显示。
/// 拖动期间显示预览值，松手后才真正 seek（与横屏进度条语义一致）。
class _PipSeekBar extends ConsumerStatefulWidget {
  final Music? music;

  const _PipSeekBar({required this.music});

  @override
  ConsumerState<_PipSeekBar> createState() => _PipSeekBarState();
}

class _PipSeekBarState extends ConsumerState<_PipSeekBar> {
  static const double _laneHeight = 10;
  static const double _barHeight = 4;
  static const double _barHeightActive = 6;
  static const double _thumbSize = 10;

  double? _dragMs;
  bool _hovering = false;

  void _previewSeek(double dx, double barWidth, double durationMs) {
    if (barWidth <= 0 || durationMs <= 0) return;
    final fraction = (dx / barWidth).clamp(0.0, 1.0);
    setState(() => _dragMs = fraction * durationMs);
  }

  Future<void> _commitSeek() async {
    final ms = _dragMs;
    if (ms == null) return;
    await ref
        .read(playbackCommandsProvider.notifier)
        .seek(Duration(milliseconds: ms.round()));
    // seek 期间用户可能已经开始下一段拖动，只有预览值未变时才清除；
    // await 期间小窗可能已退出，必须先判 mounted
    if (mounted && _dragMs == ms) {
      setState(() => _dragMs = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider);
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final textSecondary = colorScheme.onSurfaceVariant;

    final duration = widget.music?.duration ?? Duration.zero;
    final durationMs = duration.inMilliseconds.toDouble();
    final effectiveMs = _dragMs ?? position.inMilliseconds.toDouble();
    final fraction = durationMs <= 0
        ? 0.0
        : (effectiveMs / durationMs).clamp(0.0, 1.0);
    final active = _hovering || _dragMs != null;
    final enabled = widget.music != null && durationMs > 0;

    final timeStyle = TextStyle(
      color: textSecondary,
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        Text(
          formatDuration(Duration(milliseconds: effectiveMs.round())),
          style: timeStyle,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return MouseRegion(
                cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: enabled
                      ? (details) => _previewSeek(
                          details.localPosition.dx,
                          barWidth,
                          durationMs,
                        )
                      : null,
                  onTapUp: enabled ? (_) => _commitSeek() : null,
                  onTapCancel: enabled
                      ? () => setState(() => _dragMs = null)
                      : null,
                  onHorizontalDragStart: enabled
                      ? (details) => _previewSeek(
                          details.localPosition.dx,
                          barWidth,
                          durationMs,
                        )
                      : null,
                  onHorizontalDragUpdate: enabled
                      ? (details) => _previewSeek(
                          details.localPosition.dx,
                          barWidth,
                          durationMs,
                        )
                      : null,
                  onHorizontalDragEnd: enabled ? (_) => _commitSeek() : null,
                  onHorizontalDragCancel: enabled
                      ? () => setState(() => _dragMs = null)
                      : null,
                  child: SizedBox(
                    height: 22,
                    child: Center(
                      child: SizedBox(
                        height: _laneHeight,
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // 轨道
                            Center(
                              child: AnimatedContainer(
                                duration: AppTokens.microDuration,
                                curve: AppTokens.standardEasing,
                                height: active ? _barHeightActive : _barHeight,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: palette.surfaceHover,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            // 已播放部分
                            FractionallySizedBox(
                              widthFactor: fraction,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: AppTokens.microDuration,
                                  curve: AppTokens.standardEasing,
                                  height: active
                                      ? _barHeightActive
                                      : _barHeight,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                            // 悬停/拖动时显示的拇指
                            if (active && enabled)
                              Align(
                                alignment: Alignment(fraction * 2 - 1, 0),
                                child: Container(
                                  width: _thumbSize,
                                  height: _thumbSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: accent,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.25,
                                        ),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
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
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(formatDuration(duration), style: timeStyle),
      ],
    );
  }
}
