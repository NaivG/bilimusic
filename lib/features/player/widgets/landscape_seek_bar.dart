import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/features/player/widgets/playback_buttons.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 横屏模式进度条组件
/// 基于ParticleMusic的SeekBar适配bilimusic的PlayerManager
class LandscapeSeekBar extends ConsumerStatefulWidget {
  final Color? color;

  /// 未播放段轨道色；为空时取 [BmColors.hairline]。
  final Color? inactiveColor;

  /// 时长文字颜色；为空时跟随 [color]，再回退 [BmColors.textSecondary]。
  final Color? labelColor;

  final double widgetHeight;
  final double seekBarHeight;
  final bool showDurationLabels;

  const LandscapeSeekBar({
    super.key,
    this.color,
    this.inactiveColor,
    this.labelColor,
    this.widgetHeight = 20,
    this.seekBarHeight = 10,
    this.showDurationLabels = true,
  });

  @override
  ConsumerState<LandscapeSeekBar> createState() => _LandscapeSeekBarState();
}

class _LandscapeSeekBarState extends ConsumerState<LandscapeSeekBar> {
  double? dragValue;
  bool isDragging = false;
  double horizontalPadding = 45;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final activeColor = widget.color ?? colors.accent;
    final inactiveColor = widget.inactiveColor ?? colors.hairline;
    final labelColor =
        widget.labelColor ?? widget.color ?? colors.textSecondary;
    final position = ref.watch(positionProvider);
    final music = ref.read(playerCoordinatorProvider).currentMusic;
    final duration = music?.duration ?? Duration.zero;
    final durationMs = duration.inMilliseconds.toDouble();

    final effectiveValue = dragValue ?? position.inMilliseconds.toDouble();
    final sliderValue = durationMs == 0
        ? 0.0
        : effectiveValue.clamp(0.0, durationMs);

    return SizedBox(
      height: widget.widgetHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (widget.showDurationLabels)
            Positioned(
              left: 0,
              right: 0,
              bottom: 2,
              child: isDragging
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(_durationOf(sliderValue)),
                          style: BmTypography.numeric(
                            type.caption.copyWith(color: labelColor),
                          ),
                        ),
                        Text(
                          formatDuration(duration),
                          style: BmTypography.numeric(
                            type.caption.copyWith(color: labelColor),
                          ),
                        ),
                      ],
                    ),
            ),

          // Slider visuals
          SizedBox(
            height: widget.seekBarHeight,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: activeColor,
                trackHeight: isDragging
                    ? widget.seekBarHeight + 4
                    : widget.seekBarHeight,
                trackShape: const FullWidthTrackShape(),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: activeColor,
                inactiveTrackColor: inactiveColor,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Slider(
                  min: 0.0,
                  max: durationMs == 0 ? 1.0 : durationMs,
                  value: sliderValue,
                  onChanged: (value) {},
                ),
              ),
            ),
          ),

          // Full-track GestureDetector
          Positioned.fill(
            top: (widget.widgetHeight - widget.seekBarHeight) / 2,
            bottom: (widget.widgetHeight - widget.seekBarHeight) / 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: (_) {
                setState(() => isDragging = false);
              },
              onTapDown: (_) {
                if (ref.read(playerCoordinatorProvider).currentMusic == null) {
                  return;
                }
                setState(() => isDragging = true);
              },
              onHorizontalDragUpdate: (details) {
                if (ref.read(playerCoordinatorProvider).currentMusic == null) {
                  return;
                }
                _seekByTouch(details.localPosition.dx, context, durationMs);
                setState(() {
                  isDragging = true;
                });
              },
              onHorizontalDragEnd: (_) async {
                if (ref.read(playerCoordinatorProvider).currentMusic == null) {
                  return;
                }
                if (dragValue != null) {
                  await ref
                      .read(playbackCommandsProvider.notifier)
                      .seek(_durationOf(dragValue!));
                }
                setState(() {
                  dragValue = null;
                  isDragging = false;
                });
              },
              onTapUp: (details) async {
                if (ref.read(playerCoordinatorProvider).currentMusic == null) {
                  return;
                }
                _seekByTouch(details.localPosition.dx, context, durationMs);
                await ref
                    .read(playbackCommandsProvider.notifier)
                    .seek(_durationOf(dragValue!));
                setState(() {
                  dragValue = null;
                  isDragging = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 毫秒值 → [Duration]（不直接写字面量，统一走微秒构造）。
  static Duration _durationOf(double milliseconds) =>
      Duration(microseconds: (milliseconds * 1000).round());

  void _seekByTouch(double dx, BuildContext context, double durationMs) {
    final box = context.findRenderObject() as RenderBox;

    double relative =
        (dx - horizontalPadding) / (box.size.width - horizontalPadding * 2);
    relative = relative.clamp(0.0, 1.0);
    dragValue = relative * durationMs;
  }
}
