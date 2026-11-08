import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Toast 语义状态：只改左侧色条，不换整块底色。
enum BmToastStatus { neutral, success, error }

/// 统一 Toast 入口。
///
/// 先清掉排队中的旧 toast，再用透明外壳的浮动 `SnackBar` 承载 [BmToast]：
/// 定位 / 边界仍由 `SnackBarThemeData` 决定，外观完全由 [BmToast] 自绘。
/// 默认停留 3 秒。
void showBmToast(
  BuildContext context,
  String message, {
  BmToastStatus status = BmToastStatus.neutral,
  Duration? duration,
}) {
  final theme = Theme.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Theme(
        data: theme,
        child: BmToast(message: message, status: status),
      ),
      duration: duration ?? const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      // 外壳只保留几何，描边由 BmToast 自己画，避免双线。
      shape: const RoundedRectangleBorder(borderRadius: BmTokens.r14All),
      elevation: 0,
      padding: EdgeInsets.zero,
    ),
  );
}

/// Lucent Toast 面板：`floating` 底 + 0.5 hairline + 14 圆角，文案 `label` 13/18。
///
/// success / error 在左侧加 2px 胶囊色条；进场从下 8px 上移 + fade 180ms，
/// reduce motion 时直接到终态。
class BmToast extends StatefulWidget {
  const BmToast({
    super.key,
    required this.message,
    this.status = BmToastStatus.neutral,
  });

  final String message;
  final BmToastStatus status;

  @override
  State<BmToast> createState() => _BmToastState();
}

class _BmToastState extends State<BmToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BmMotion.medium,
  );
  late final CurvedAnimation _animation = CurvedAnimation(
    parent: _controller,
    curve: BmMotion.standard,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final statusColor = switch (widget.status) {
      BmToastStatus.neutral => null,
      BmToastStatus.success => colors.success,
      BmToastStatus.error => colors.danger,
    };
    final surface = Material(
      color: colors.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BmTokens.r14All,
        side: BorderSide(color: colors.hairline, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s3,
          vertical: BmTokens.s2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusColor != null) ...[
              Container(
                width: 2,
                height: BmTokens.s4,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BmTokens.rPillAll,
                ),
              ),
              const SizedBox(width: BmTokens.s2),
            ],
            Flexible(
              child: Text(
                widget.message,
                style: type.label.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
    if (reduceMotionOf(context)) return surface;
    return AnimatedBuilder(
      animation: _animation,
      child: surface,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _animation.value) * BmTokens.s2),
            child: child,
          ),
        );
      },
    );
  }
}
