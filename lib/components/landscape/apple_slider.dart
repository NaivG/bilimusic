import 'package:flutter/material.dart';

/// Apple Music 风格的进度条组件
/// 简洁白色设计，带触摸反馈
class AppleMusicSlider extends StatefulWidget {
  final Duration position;
  final Duration? duration;
  final Function(Duration)? onSeek;
  final double trackHeight;
  final double thumbRadius;
  final double activeTrackColor;
  final double inactiveTrackColor;

  const AppleMusicSlider({
    super.key,
    required this.position,
    this.duration,
    this.onSeek,
    this.trackHeight = 4.0,
    this.thumbRadius = 6.0,
    this.activeTrackColor = 1.0,
    this.inactiveTrackColor = 0.3,
  });

  @override
  State<AppleMusicSlider> createState() => _AppleMusicSliderState();
}

class _AppleMusicSliderState extends State<AppleMusicSlider> {
  bool _isDragging = false;
  double? _dragValue;

  double get _progress {
    if (widget.duration == null || widget.duration!.inSeconds == 0) {
      return 0.0;
    }
    if (_isDragging && _dragValue != null) {
      return _dragValue!.clamp(0.0, 1.0);
    }
    return (widget.position.inSeconds / widget.duration!.inSeconds).clamp(
      0.0,
      1.0,
    );
  }

  void _handleChange(double value) {
    setState(() {
      _dragValue = value;
    });
  }

  void _handleChangeStart(double value) {
    setState(() {
      _isDragging = true;
      _dragValue = value;
    });
  }

  void _handleChangeEnd(double value) {
    if (widget.duration != null) {
      final newPosition = Duration(
        seconds: (value * widget.duration!.inSeconds).toInt(),
      );
      widget.onSeek?.call(newPosition);
    }
    setState(() {
      _isDragging = false;
      _dragValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // 分配空间：Slider 占 60%，时间显示占 40%
        final sliderHeight = availableHeight * 0.6;
        final timeDisplayHeight = availableHeight * 0.4;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条 Slider
            SizedBox(
              height: sliderHeight,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: widget.trackHeight,
                  thumbShape: _AppleMusicThumbShape(
                    radius: _isDragging
                        ? widget.thumbRadius * 1.3
                        : widget.thumbRadius,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 20,
                  ),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(
                    alpha: widget.inactiveTrackColor,
                  ),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.2),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: _progress,
                  onChanged: _handleChange,
                  onChangeStart: _handleChangeStart,
                  onChangeEnd: _handleChangeEnd,
                ),
              ),
            ),
            // 时间显示
            SizedBox(height: timeDisplayHeight, child: _buildTimeDisplay()),
          ],
        );
      },
    );
  }

  Widget _buildTimeDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _formatDuration(
              _isDragging && _dragValue != null && widget.duration != null
                  ? Duration(
                      seconds: (_dragValue! * widget.duration!.inSeconds)
                          .toInt(),
                    )
                  : widget.position,
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            _formatDuration(widget.duration ?? Duration.zero),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

/// Apple Music 风格滑块形状
class _AppleMusicThumbShape extends SliderComponentShape {
  final double radius;

  const _AppleMusicThumbShape({required this.radius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(radius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // 绘制滑块阴影
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(0, 2), radius, shadowPaint);

    // 绘制滑块
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);
  }
}

/// 带动画的进度条组件
class AnimatedAppleMusicSlider extends StatelessWidget {
  final Duration position;
  final Duration? duration;
  final Function(Duration)? onSeek;

  const AnimatedAppleMusicSlider({
    super.key,
    required this.position,
    this.duration,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 100),
      child: AppleMusicSlider(
        key: ValueKey('$position'),
        position: position,
        duration: duration,
        onSeek: onSeek,
      ),
    );
  }
}
