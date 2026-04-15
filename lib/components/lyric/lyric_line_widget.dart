import 'package:flutter/material.dart';
import 'package:bilimusic/utils/lyric_parser.dart';

/// 单条歌词组件
/// 支持当前行高亮、缩放动画和点击跳转
class LyricLineWidget extends StatelessWidget {
  final LyricLine line;
  final bool isCurrentLine;
  final double currentFontSize;
  final double otherFontSize;
  final Duration animationDuration;
  final Curve animationCurve;
  final Function(Duration)? onTap;

  const LyricLineWidget({
    super.key,
    required this.line,
    required this.isCurrentLine,
    this.currentFontSize = 24,
    this.otherFontSize = 16,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeOutCubic,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap?.call(Duration(seconds: line.time.toInt())),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AnimatedDefaultTextStyle(
          duration: animationDuration,
          curve: animationCurve,
          style: TextStyle(
            fontSize: isCurrentLine ? currentFontSize : otherFontSize,
            fontWeight: isCurrentLine ? FontWeight.w700 : FontWeight.w500,
            color: isCurrentLine
                ? Colors.white
                : Colors.white.withValues(alpha: 0.45),
            height: 1.5,
          ),
          textAlign: TextAlign.left,
          child: Text(line.content),
        ),
      ),
    );
  }
}
