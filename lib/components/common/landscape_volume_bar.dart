import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 横屏模式音量条组件
/// 基于ParticleMusic的VolumeBar适配bilimusic
class LandscapeVolumeBar extends StatefulWidget {
  final Color activeColor;
  final double width;
  final double height;

  const LandscapeVolumeBar({
    super.key,
    required this.activeColor,
    this.width = 120,
    this.height = 20,
  });

  @override
  State<LandscapeVolumeBar> createState() => _LandscapeVolumeBarState();
}

class _LandscapeVolumeBarState extends State<LandscapeVolumeBar> {
  double _volume = 0.7; // 默认音量70%

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          trackShape: const _FullWidthTrackShape(),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
          overlayColor: Colors.transparent,
          activeTrackColor: widget.activeColor,
          inactiveTrackColor: Colors.black12,
        ),
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              double step = 0.02;

              double newValue;
              if (event.scrollDelta.dy < 0) {
                newValue = _volume + step;
              } else {
                newValue = _volume - step;
              }

              newValue = newValue.clamp(0.0, 1.0);
              setState(() {
                _volume = newValue;
              });
              // TODO: 集成bilimusic音量控制（如果可用）
            }
          },
          child: Slider(
            value: _volume,
            min: 0,
            max: 1,
            onChanged: (value) {
              setState(() {
                _volume = value;
              });
              // TODO: 集成bilimusic音量控制（如果可用）
            },
          ),
        ),
      ),
    );
  }
}

/// 全宽度轨道形状（用于音量条）
class _FullWidthTrackShape extends SliderTrackShape {
  const _FullWidthTrackShape();

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
