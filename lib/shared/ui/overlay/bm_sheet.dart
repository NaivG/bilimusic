import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_overlay_routes.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 打开 Lucent 底部单，返回 `Navigator.pop` 的结果。
///
/// 面板弹簧进场（≤500ms）、240ms 退场，支持跟手拖拽关闭；
/// [maxHeightFactor] 限制面板最大高度占屏幕的比例。
Future<T?> showBmSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  double maxHeightFactor = 0.9,
}) {
  final theme = Theme.of(context);
  return Navigator.of(context).push<T>(
    BmSheetRoute<T>(
      builder: builder,
      theme: theme,
      barrierColor: BmColors.of(context).scrim,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierDismissible: isDismissible,
      maxHeightFactor: maxHeightFactor,
      reduceMotion: reduceMotionOf(context),
    ),
  );
}

/// Lucent 底部单面板。
///
/// 顶部 20 圆角、`floating` 底 + 0.5 hairline；[showHandle] 时画 36×4 胶囊
/// handle；内容内边距默认水平 20 / 垂直 16。键盘弹出只做 180ms 的 padding
/// 过渡；可滚动内容由调用方自己放 `ListView`。
class BmSheet extends StatelessWidget {
  const BmSheet({
    super.key,
    required this.child,
    this.showHandle = true,
    this.padding,
  });

  final Widget child;

  /// 是否显示顶部拖拽 handle。
  final bool showHandle;

  /// 内容内边距；默认水平 20 / 垂直 16。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final insets = MediaQuery.viewInsetsOf(context);
    final resolvedPadding =
        padding ??
        const EdgeInsets.symmetric(
          horizontal: BmTokens.s5,
          vertical: BmTokens.s4,
        );
    return SizedBox(
      // 底部单通栏：内容只决定高度，宽度铺满可用空间。
      width: double.infinity,
      child: Material(
        color: colors.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(BmTokens.r20),
          ),
          side: BorderSide(color: colors.hairline, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedPadding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          duration: motionDuration(context, BmMotion.medium),
          curve: motionCurve(context, BmMotion.standard),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle) _BmSheetHandle(color: colors.textTertiary),
                Flexible(
                  child: Padding(padding: resolvedPadding, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部拖拽 handle：36×4 胶囊。
class _BmSheetHandle extends StatelessWidget {
  const _BmSheetHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: BmTokens.s2, bottom: BmTokens.s1),
      child: Center(
        child: Container(
          width: BmTokens.s8 + BmTokens.s1,
          height: BmTokens.s1,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BmTokens.rPillAll,
          ),
        ),
      ),
    );
  }
}
