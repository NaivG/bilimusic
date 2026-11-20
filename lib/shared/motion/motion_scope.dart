import 'package:flutter/widgets.dart';

import 'motion_tokens.dart';

/// 子树级 reduce-motion 开关。
///
/// 优先级高于 `MediaQuery.disableAnimations`：预览页 / 测试用它一次性
/// 关掉整段演示，不必改系统设置。
class BmMotionScope extends InheritedWidget {
  const BmMotionScope({
    super.key,
    required this.reduceMotion,
    required super.child,
  });

  final bool reduceMotion;

  /// 取最近的 scope 值；没有 scope 时返回 null。
  static bool? maybeReduceMotionOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BmMotionScope>()
        ?.reduceMotion;
  }

  @override
  bool updateShouldNotify(BmMotionScope oldWidget) =>
      reduceMotion != oldWidget.reduceMotion;
}

/// 当前上下文是否关闭位移/缩放动效。
bool reduceMotionOf(BuildContext context) {
  final scoped = BmMotionScope.maybeReduceMotionOf(context);
  if (scoped != null) return scoped;
  return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// 所有动画时长都必须过这里；reduce motion 时归零。
Duration motionDuration(BuildContext context, Duration duration) {
  return reduceMotionOf(context) ? Duration.zero : duration;
}

/// reduce motion 下只保留 ≤120ms 的透明度过渡。
Duration fadeDuration(BuildContext context, Duration duration) {
  if (!reduceMotionOf(context)) return duration;
  return duration <= BmMotion.small ? duration : BmMotion.small;
}

/// reduce motion 下空间移动退化为线性，避免“假装有方向”。
Curve motionCurve(BuildContext context, Curve curve) {
  return reduceMotionOf(context) ? BmMotion.linear : curve;
}
