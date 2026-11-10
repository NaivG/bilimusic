import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 加载骨架：一块 `bgDeep` 占位，带 1200ms 呼吸式的明暗循环。
///
/// 只在首屏 / 列表加载时用；已有内容时不要叠在真内容上。
class BmSkeleton extends StatefulWidget {
  const BmSkeleton({
    super.key,
    this.width,
    this.height = BmTokens.s4,
    this.radius = BmTokens.r9All,
  });

  final double? width;
  final double height;
  final BorderRadiusGeometry radius;

  /// 一行「封面 + 两行线」的列表占位。
  static Widget row({double coverSize = BmTokens.controlMd}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s4,
        vertical: BmTokens.s2,
      ),
      child: Row(
        children: [
          BmSkeleton(
            width: coverSize,
            height: coverSize,
            radius: BmTokens.albumArtRadius,
          ),
          const SizedBox(width: BmTokens.s3),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BmSkeleton(height: BmTokens.s3),
                SizedBox(height: BmTokens.s2),
                BmSkeleton(width: 120, height: BmTokens.s2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 四行列表占位。
  static Widget list({int count = 4}) =>
      Column(children: [for (var i = 0; i < count; i++) BmSkeleton.row()]);

  @override
  State<BmSkeleton> createState() => _BmSkeletonState();
}

class _BmSkeletonState extends State<BmSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BmMotion.hero,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = reduceMotionOf(context) ? 0.5 : _controller.value;
        return Opacity(
          opacity: 0.45 + 0.35 * t,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: colors.bgDeep,
              borderRadius: widget.radius,
            ),
          ),
        );
      },
    );
  }
}
