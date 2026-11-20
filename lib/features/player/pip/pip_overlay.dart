import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/now_playing/color_extractor.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/pip/pip_service.dart';
import 'package:bilimusic/features/player/widgets/crossfade_indicator.dart';
import 'package:bilimusic/features/player/widgets/playback_buttons.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart'
    show currentMusicProvider;
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/stage/bm_audio_quality_badge.dart';
import 'package:bilimusic/shared/ui/stage/bm_stage_backdrop.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/animations.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/widgets/music_cover.dart';

/// 小窗专用紧凑尺寸：窗口内容只有约 134 逻辑像素高，详情页控制行的常规尺寸放不下。
const double _closeButtonSize = 24;
const double _sideButtonSize = 30;
const double _mainButtonSize = 36;

/// 桌面端画中画（PiP）小窗。
class PipOverlay extends ConsumerWidget {
  const PipOverlay({super.key});

  /// 内容四周留白：Stage 卡片的 s3。
  static const EdgeInsets _padding = EdgeInsets.all(BmTokens.s3);

  /// 封面缩略图边长上限；窗口被拉高时不让封面吞掉控制区。
  static const double _maxCover = 176;

  /// 系统字号放大的上限。窗口高度固定，1.2 倍是右栏还能完整放下的极限。
  static const double _maxTextScale = 1.2;

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
    final music = ref.watch(currentMusicProvider);
    final playerState = ref.watch(playerStateProvider);
    final fluid = ref.watch(
      settingsProvider.select((settings) => settings.fluidBackground),
    );

    // 小窗背景透明：圆角靠 ClipRRect 裁，角上露出的桌面由窗口透明度负责，
    // 不能再垫一层不透明的 Scaffold 底色，否则圆角会被填成直角。
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTextScale,
        child: ClipRRect(
          borderRadius: BmTokens.r14All,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PipStageBackdrop(music: music, fluid: fluid),
              const _PipStageScrim(),
              // 拖动层垫在内容下面：Text / Image 的 RenderObject 会吸收命中，
              // 所以下面把封面、文字这些非交互子树包进 IgnorePointer，
              // 让它们落到这一层上。
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
              Padding(
                padding: _padding,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final coverSize = math.min(
                      constraints.maxHeight,
                      math.min(_maxCover, constraints.maxWidth * 0.42),
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IgnorePointer(
                          child: _PipCover(music: music, size: coverSize),
                        ),
                        const SizedBox(width: BmTokens.s3),
                        Expanded(
                          child: _PipControlPanel(
                            music: music,
                            playerState: playerState,
                            onTogglePlay: () => _togglePlay(playerState, ref),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stage 打底：封面虚化 / 主色纯色，跟随设置里的「流体背景效果」。
///
/// 封面主色优先命中 [ColorExtractor] 的缓存；没取过色时先留旧色，
/// 等异步结果回来再让 [BmStageBackdrop] 做颜色过渡。
class _PipStageBackdrop extends StatefulWidget {
  const _PipStageBackdrop({required this.music, required this.fluid});

  final Music? music;
  final bool fluid;

  @override
  State<_PipStageBackdrop> createState() => _PipStageBackdropState();
}

class _PipStageBackdropState extends State<_PipStageBackdrop> {
  String _coverUrl = '';
  Color? _dominantColor;

  @override
  void initState() {
    super.initState();
    _track(widget.music?.coverUrl ?? '');
  }

  @override
  void didUpdateWidget(_PipStageBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.music?.coverUrl != widget.music?.coverUrl) {
      _track(widget.music?.coverUrl ?? '');
    }
  }

  /// 记录当前封面主色。同步命中缓存时不 setState：调用点后紧跟一次 build。
  void _track(String coverUrl) {
    _coverUrl = coverUrl;
    if (coverUrl.isEmpty) {
      _dominantColor = null;
      return;
    }
    final cached = ColorExtractor.cachedColorOf(coverUrl);
    if (cached != null) {
      _dominantColor = cached;
      return;
    }

    final requested = coverUrl;
    unawaited(
      ColorExtractor.extractColorFromUrl(requested).then((color) {
        if (!mounted || _coverUrl != requested) return;
        setState(() => _dominantColor = color);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BmStageBackdrop(
      coverUrl: _coverUrl,
      dominantColor: _dominantColor,
      fallbackColor: Theme.of(context).colorScheme.primary,
      fluid: widget.fluid,
      cacheManager: imageCacheManager,
    );
  }
}

/// 文字可读性遮罩：整体压暗 + 文字列（右半边）再压深一档。
///
/// 封面虚化层亮度不可控（近白封面会把白字压到 4.5:1 以下），而小窗的曲名
/// 直接从封面右缘开始，比详情页（文字在封面下方、另有底部渐暗）更需要压暗。
/// 这里只压背景，不压左侧封面缩略图（封面画在遮罩之上）。
/// 透明度是艺术化压暗，不套 UI 状态层档位。
class _PipStageScrim extends StatelessWidget {
  const _PipStageScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[Color(0x00000000), Color(0x8C000000)],
            stops: <double>[0.05, 1.0],
          ),
        ),
        child: ColoredBox(color: Color(0x40000000)),
      ),
    );
  }
}

/// 左侧封面缩略图。
///
/// 切歌动画：旧封面向左滑出 + 淡出，新封面自右滑入 + 淡入。
/// 不用 AnimatedSwitcher——两个子项需要相反方向的位移，
/// 用单个 AnimationController 显式编排入场/出场两份动画。
class _PipCover extends StatefulWidget {
  const _PipCover({required this.music, required this.size});

  final Music? music;
  final double size;

  @override
  State<_PipCover> createState() => _PipCoverState();
}

class _PipCoverState extends State<_PipCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BmMotion.xlarge,
  )..addStatusListener(_onStatus);

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
  }

  @override
  void didUpdateWidget(covariant _PipCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // key 含 bvid + cid，是队列域的唯一标识。
    if (oldWidget.music?.key != widget.music?.key) {
      final reduceMotion = reduceMotionOf(context);
      setState(() {
        // reduce motion 下不留旧封面，避免控制器已停在终点时状态回调
        // 不再触发、_outgoing 永远清不掉。
        _outgoing = reduceMotion ? null : _current;
        _current = widget.music;
      });
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _outgoing != null) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _cover(BuildContext context, Music? music) {
    final colors = context.bmColors;
    return MusicCover(
      music: music,
      size: widget.size,
      radius: null,
      placeholderColor: colors.stageControlFill,
      placeholderIconColor: colors.stageTextSecondary,
      fadeInDuration: motionDuration(context, BmMotion.medium),
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.size;
    final currentCover = _cover(context, _current);
    final outgoingCover = _outgoing == null ? null : _cover(context, _outgoing);

    return SizedBox(
      // 钉死边长
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BmTokens.r10All,
          boxShadow: [
            BoxShadow(
              color: context.bmColors.shadowStrong,
              blurRadius: BmTokens.s4,
              offset: const Offset(0, BmTokens.s1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BmTokens.r10All,
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
                // 无动画期直接平铺，避免首帧停留在 opacity 0。
                Positioned.fill(child: currentCover),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右侧控制面板：曲名 / 歌手 / 进度条 / 传输控件
class _PipControlPanel extends ConsumerWidget {
  const _PipControlPanel({
    required this.music,
    required this.playerState,
    required this.onTogglePlay,
  });

  final Music? music;
  final PlayerState playerState;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final hasMusic = music != null;
    final isPlaying = playerState is PlayerPlaying;
    final fading = isCrossfading(playerState);
    final commands = ref.read(playbackCommandsProvider.notifier);
    final actualQuality = ref.watch(actualQualityProvider);
    final qualityId = actualQuality.isEmpty
        ? ref.watch(
            settingsProvider.select((settings) => settings.audioQuality),
          )
        : actualQuality;

    // 没有曲目时按钮不可用：用统一的禁用档压暗图标，避免无底色按钮看不出禁用。
    final controlColor = hasMusic
        ? colors.stageText
        : colors.stageText.withValues(alpha: BmAlpha.disabled);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              // 非交互文字不吸收命中，让空白/文字处也能起拖窗口。
              child: IgnorePointer(
                child: Text(
                  music?.title ?? 'Not Playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodyStrong.copyWith(color: colors.stageText),
                ),
              ),
            ),
            const SizedBox(width: BmTokens.s2),
            PlaybackControlButton(
              icon: Icons.close_rounded,
              size: _closeButtonSize,
              iconSize: BmTokens.iconInline,
              iconColor: colors.stageText,
              semanticLabel: '退出小窗',
              onTap: () => PipService().exitPipMode(),
            ),
          ],
        ),
        if (hasMusic) ...[
          const SizedBox(height: 2),
          IgnorePointer(
            child: AnimatedSwitcher(
              duration: BmMotion.medium,
              transitionBuilder: switcherFadeTransition,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              ),
              child: fading
                  ? const CrossfadeIndicator(key: ValueKey('crossfade'))
                  : Text(
                      music!.artist.displayName,
                      key: const ValueKey('artist'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.caption.copyWith(
                        color: colors.stageTextSecondary,
                      ),
                    ),
            ),
          ),
        ],
        const Spacer(),
        _PipSeekBar(music: music),
        const SizedBox(height: BmTokens.s1),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlaybackControlButton(
                    icon: Icons.skip_previous_rounded,
                    size: _sideButtonSize,
                    iconSize: BmTokens.icon,
                    iconColor: controlColor,
                    semanticLabel: '上一首',
                    onTap: hasMusic ? () => commands.playPrevious() : null,
                  ),
                  const SizedBox(width: BmTokens.s2),
                  PlaybackPlayPauseButton(
                    isPlaying: isPlaying,
                    size: _mainButtonSize,
                    iconSize: BmTokens.iconLarge,
                    iconColor: controlColor,
                    semanticLabel: isPlaying ? '暂停' : '播放',
                    onTap: hasMusic ? onTogglePlay : null,
                  ),
                  const SizedBox(width: BmTokens.s2),
                  PlaybackControlButton(
                    icon: Icons.skip_next_rounded,
                    size: _sideButtonSize,
                    iconSize: BmTokens.icon,
                    iconColor: controlColor,
                    semanticLabel: '下一首',
                    onTap: hasMusic ? () => commands.playNext() : null,
                  ),
                ],
              ),
            ),
            if (hasMusic)
              IgnorePointer(child: BmAudioQualityBadge(qualityId: qualityId)),
          ],
        ),
      ],
    );
  }
}

/// 可拖动进度条 + 时间显示。
/// 拖动期间显示预览值，松手后才真正 seek（与横屏进度条语义一致）。
class _PipSeekBar extends ConsumerStatefulWidget {
  const _PipSeekBar({required this.music});

  final Music? music;

  @override
  ConsumerState<_PipSeekBar> createState() => _PipSeekBarState();
}

class _PipSeekBarState extends ConsumerState<_PipSeekBar> {
  static const double _laneHeight = 10;
  static const double _barHeight = 3;
  static const double _barHeightActive = 4;
  static const double _thumbSize = 7;

  /// 读屏/键盘微调步长。
  static const Duration _nudgeStep = Duration(seconds: 5);

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
    // await 期间小窗可能已退出，必须先判 mounted。
    if (mounted && _dragMs == ms) {
      setState(() => _dragMs = null);
    }
  }

  /// 无障碍微调：在当前进度上前后跳 5 秒，夹在 [0, duration] 内。
  Future<void> _nudge(Duration delta) async {
    final duration = widget.music?.duration ?? Duration.zero;
    final current = ref.read(positionProvider);
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await ref.read(playbackCommandsProvider.notifier).seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider);
    final colors = context.bmColors;
    final type = context.bmType;

    final duration = widget.music?.duration ?? Duration.zero;
    final durationMs = duration.inMilliseconds.toDouble();
    final effectiveMs = _dragMs ?? position.inMilliseconds.toDouble();
    final fraction = durationMs <= 0
        ? 0.0
        : (effectiveMs / durationMs).clamp(0.0, 1.0);
    final active = _hovering || _dragMs != null;
    final enabled = widget.music != null && durationMs > 0;

    final positionLabel = formatDuration(
      Duration(milliseconds: effectiveMs.round()),
    );
    final durationLabel = formatDuration(duration);
    final timeStyle = BmTypography.numeric(
      type.micro.copyWith(color: colors.stageTextSecondary),
    );

    return Row(
      children: [
        IgnorePointer(child: Text(positionLabel, style: timeStyle)),
        const SizedBox(width: BmTokens.s2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Semantics(
                slider: true,
                enabled: enabled,
                label: '播放进度',
                value: '$positionLabel / $durationLabel',
                onIncrease: enabled
                    ? () => unawaited(_nudge(_nudgeStep))
                    : null,
                onDecrease: enabled
                    ? () => unawaited(_nudge(-_nudgeStep))
                    : null,
                child: MouseRegion(
                  cursor: enabled
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
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
                      height: 20,
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
                                  duration: motionDuration(
                                    context,
                                    BmMotion.small,
                                  ),
                                  curve: BmMotion.standard,
                                  height: active
                                      ? _barHeightActive
                                      : _barHeight,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: colors.stageBorder,
                                    borderRadius: BmTokens.rPillAll,
                                  ),
                                ),
                              ),
                              // 已播放部分
                              FractionallySizedBox(
                                widthFactor: fraction,
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: motionDuration(
                                      context,
                                      BmMotion.small,
                                    ),
                                    curve: BmMotion.standard,
                                    height: active
                                        ? _barHeightActive
                                        : _barHeight,
                                    decoration: BoxDecoration(
                                      color: colors.stageText,
                                      borderRadius: BmTokens.rPillAll,
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
                                      color: colors.stageText,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colors.shadow,
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
                ),
              );
            },
          ),
        ),
        const SizedBox(width: BmTokens.s2),
        IgnorePointer(child: Text(durationLabel, style: timeStyle)),
      ],
    );
  }
}
