import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/providers/playback_providers.dart';

/// 横屏模式进度条组件
/// 基于ParticleMusic的SeekBar适配bilimusic的PlayerManager
class LandscapeSeekBar extends ConsumerStatefulWidget {
  final Color? color;
  final double widgetHeight;
  final double seekBarHeight;
  final bool showDurationLabels;

  const LandscapeSeekBar({
    super.key,
    this.color,
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
                          _formatDuration(
                            Duration(milliseconds: sliderValue.toInt()),
                          ),
                          style: TextStyle(
                            color: widget.color ?? Colors.grey,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            color: widget.color ?? Colors.grey,
                            fontSize: 12.5,
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
                thumbColor: widget.color ?? Colors.grey,
                trackHeight: isDragging ? 4 : 2,
                trackShape: const FullWidthTrackShape(),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: widget.color ?? Colors.grey,
                inactiveTrackColor: Colors.black12,
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
                  await ref.read(playbackCommandsProvider.notifier).seek(
                    Duration(milliseconds: dragValue!.toInt()),
                  );
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
                await ref.read(playbackCommandsProvider.notifier).seek(
                  Duration(milliseconds: dragValue!.toInt()),
                );
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

  void _seekByTouch(double dx, BuildContext context, double durationMs) {
    final box = context.findRenderObject() as RenderBox;

    double relative =
        (dx - horizontalPadding) / (box.size.width - horizontalPadding * 2);
    relative = relative.clamp(0.0, 1.0);
    dragValue = relative * durationMs;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 全宽度轨道形状（用于seekbar）
class FullWidthTrackShape extends SliderTrackShape {
  const FullWidthTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );

    final trackPaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.black12
      ..style = PaintingStyle.fill;

    final radius = Radius.circular(trackRect.height / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      trackPaint,
    );

    final activeTrackRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );

    final activeTrackPaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.black
      ..style = PaintingStyle.fill;

    context.canvas.drawRRect(
      RRect.fromRectAndRadius(activeTrackRect, radius),
      activeTrackPaint,
    );
  }
}
