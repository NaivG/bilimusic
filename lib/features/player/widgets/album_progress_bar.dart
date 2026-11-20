import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 详情页进度区块（Apple Music Classical 结构）
///
/// ```
/// ─────────────●────────────────   ← 全宽轨道（8px），可点可拖
/// 1:26           [音质]        3:20   ← 已播 / 中心位 / 总时长
/// ```
class AlbumProgressBar extends ConsumerStatefulWidget {
  const AlbumProgressBar({
    super.key,
    required this.duration,
    this.centerLabel,
    this.activeColor,
    this.inactiveColor,
    this.labelColor,
    this.barHeight = defaultBarHeight,
    this.hitHeight = defaultHitHeight,
    this.gap = defaultGap,
  });

  /// 轨道默认视觉高度：与旧版进度条（8px）持平，不再走 AM 的 4px 细线。
  static const double defaultBarHeight = 8;

  /// 轨道默认命中高度：轨道上下各留 6，读数行贴在轨道下方。
  static const double defaultHitHeight = 20;

  /// 轨道与读数行的默认间距（读数行自带约 4 的行内留白）。
  static const double defaultGap = 3;

  /// 当前曲目总时长（由宿主下发，组件不去读播放器/协调器）。
  final Duration duration;

  /// 轨道下方的中心位（音质徽标 / crossfade「过渡中」）；为空时只留两侧读数。
  final Widget? centerLabel;

  final Color? activeColor;
  final Color? inactiveColor;
  final Color? labelColor;

  /// 轨道视觉高度。
  final double barHeight;

  /// 轨道可点 / 可拖的纵向命中高度（视觉只有 [barHeight] 高）。
  final double hitHeight;

  /// 轨道与读数行的间距。
  final double gap;

  @override
  ConsumerState<AlbumProgressBar> createState() => _AlbumProgressBarState();
}

class _AlbumProgressBarState extends ConsumerState<AlbumProgressBar> {
  /// 拖动中的目标毫秒；null 表示未拖动，读数取真实播放进度。
  double? _dragMs;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final type = context.bmType;
    final position = ref.watch(positionProvider);
    final duration = widget.duration;
    final durationMs = duration.inMilliseconds.toDouble();

    final shownMs = _dragMs ?? position.inMilliseconds.toDouble();
    final clampedMs = durationMs <= 0
        ? 0.0
        : shownMs.clamp(0.0, durationMs).toDouble();
    final progress = durationMs <= 0 ? 0.0 : clampedMs / durationMs;

    final labelColor = widget.labelColor ?? Colors.white.withValues(alpha: 0.6);
    final timeStyle = BmTypography.numeric(
      type.caption.copyWith(color: labelColor, letterSpacing: 0.4),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTrack(durationMs, progress),
        SizedBox(height: widget.gap),
        _buildReadoutRow(timeStyle, clampedMs, duration),
      ],
    );
  }

  Widget _buildTrack(double durationMs, double progress) {
    final activeColor = widget.activeColor ?? Colors.white;
    final inactiveColor =
        widget.inactiveColor ?? Colors.white.withValues(alpha: 0.22);
    // 拖动时轨道加粗，给手指一个「抓住了」的反馈（与旧版一致）。
    final trackHeight = _dragging ? widget.barHeight + 2 : widget.barHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          slider: true,
          label: '播放进度',
          value: formatDuration(
            Duration(microseconds: (progress * durationMs * 1000).round()),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _previewAt(details.localPosition.dx, width, durationMs),
            onTapUp: (_) => _commitSeek(),
            onTapCancel: _cancelDrag,
            onHorizontalDragStart: (details) =>
                _previewAt(details.localPosition.dx, width, durationMs),
            onHorizontalDragUpdate: (details) =>
                _previewAt(details.localPosition.dx, width, durationMs),
            onHorizontalDragEnd: (_) => _commitSeek(),
            onHorizontalDragCancel: _cancelDrag,
            child: SizedBox(
              height: widget.hitHeight,
              width: double.infinity,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                  child: SizedBox(
                    height: trackHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: inactiveColor),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: ColoredBox(color: activeColor),
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
    );
  }

  Widget _buildReadoutRow(TextStyle style, double shownMs, Duration duration) {
    final shown = Duration(microseconds: (shownMs * 1000).round());
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            Text(formatDuration(shown), style: style),
            const Spacer(),
            Text(formatDuration(duration), style: style),
          ],
        ),
        if (widget.centerLabel != null) widget.centerLabel!,
      ],
    );
  }

  /// 指针位置 → 拖动预览（不提交 seek）。
  void _previewAt(double dx, double width, double durationMs) {
    if (durationMs <= 0 || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragging = true;
      _dragMs = fraction * durationMs;
    });
  }

  void _commitSeek() {
    final target = _dragMs;
    setState(() {
      _dragging = false;
      _dragMs = null;
    });
    if (target == null) return;
    ref
        .read(playbackCommandsProvider.notifier)
        .seek(Duration(microseconds: (target * 1000).round()));
  }

  void _cancelDrag() {
    if (!_dragging && _dragMs == null) return;
    setState(() {
      _dragging = false;
      _dragMs = null;
    });
  }
}
