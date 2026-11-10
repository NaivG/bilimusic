import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion_tokens.dart';

/// 对话框路由：遮罩线性淡入，面板 fade + scale 0.94→1。
///
/// 面板由调用方通过 [builder] 提供；路由只承担转场，不含色值，
/// 遮罩色、调用点主题与 reduce motion 都由 `showBmDialog` 传入。
class BmDialogRoute<T> extends PopupRoute<T> {
  BmDialogRoute({
    required this.builder,
    required this.theme,
    required this.barrierColor,
    this.barrierLabel,
    this.barrierDismissible = true,
    this.reduceMotion = false,
    super.settings,
  });

  /// 面板内容。
  final WidgetBuilder builder;

  /// 调用点当时的主题，在页面里原样注入。
  final ThemeData theme;

  @override
  final Color barrierColor;

  @override
  final String? barrierLabel;

  @override
  final bool barrierDismissible;

  /// reduce motion 下只保留透明度过渡。
  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? BmMotion.small : BmMotion.medium;

  @override
  Duration get reverseTransitionDuration => BmMotion.small;

  @override
  Curve get barrierCurve => BmMotion.linear;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final panel = Theme(
      data: theme,
      child: Builder(builder: builder),
    );
    final Widget content;
    if (reduceMotion) {
      content = FadeTransition(opacity: animation, child: panel);
    } else {
      final curved = animation.drive(CurveTween(curve: BmMotion.emphasized));
      content = FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: panel,
        ),
      );
    }
    return SafeArea(child: Center(child: content));
  }
}

/// 底部单路由：面板自底部滑入，进场走 [BmMotion.sheetSpring] 弹簧，
/// 退场 [BmMotion.large]；支持跟手拖拽关闭。
///
/// 拖拽时直接改写动画控制器的值（0..1），松手按位移 / 速度决定关闭或弹回；
/// 内层滚动视图会自己赢得手势竞争，外层的竖向拖拽只处理面板空白处。
class BmSheetRoute<T> extends PopupRoute<T> {
  BmSheetRoute({
    required this.builder,
    required this.theme,
    required this.barrierColor,
    this.barrierLabel,
    this.barrierDismissible = true,
    this.maxHeightFactor = 0.9,
    this.reduceMotion = false,
    super.settings,
  }) : assert(
         maxHeightFactor > 0 && maxHeightFactor <= 1,
         'maxHeightFactor 必须在 (0, 1] 内',
       );

  /// 面板内容。
  final WidgetBuilder builder;

  /// 调用点当时的主题，在页面里原样注入。
  final ThemeData theme;

  @override
  final Color barrierColor;

  @override
  final String? barrierLabel;

  @override
  final bool barrierDismissible;

  /// 面板最大高度占屏幕高度的比例。
  final double maxHeightFactor;

  /// reduce motion 下只保留透明度过渡，拖拽也退化为透明度跟手。
  final bool reduceMotion;

  // 弹簧通过 createSimulation 交给 didPush → animateWith，
  // 控制器时长只作为退场预算。
  @override
  Duration get transitionDuration =>
      reduceMotion ? BmMotion.small : BmMotion.sheetMax;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? BmMotion.small : BmMotion.large;

  @override
  Curve get barrierCurve => BmMotion.linear;

  @override
  Simulation? createSimulation({required bool forward}) {
    if (!forward || reduceMotion) return null;
    return SpringSimulation(BmMotion.sheetSpring, 0, 1, 0);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight * maxHeightFactor;
        final dragHeight = maxHeight > 0 ? maxHeight : constraints.maxHeight;
        Widget panel = Theme(
          data: theme,
          child: Builder(builder: builder),
        );
        panel = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: panel,
        );
        panel = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) => _handleDragStart(),
          onVerticalDragUpdate: (details) =>
              _handleDragUpdate(details, dragHeight),
          onVerticalDragEnd: (details) => _handleDragEnd(details, dragHeight),
          onVerticalDragCancel: _handleDragCancel,
          child: panel,
        );
        // 位移与拖拽共用 dragHeight 折算，短面板也能真正跟手。
        panel = reduceMotion
            ? FadeTransition(opacity: animation, child: panel)
            : AnimatedBuilder(
                animation: animation,
                child: panel,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, (1 - animation.value) * dragHeight),
                    child: child,
                  );
                },
              );
        return Align(alignment: Alignment.bottomCenter, child: panel);
      },
    );
  }

  void _handleDragStart() {
    final controller = this.controller;
    if (controller == null || controller.status == AnimationStatus.reverse) {
      return;
    }
    controller.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details, double dragHeight) {
    final controller = this.controller;
    if (controller == null ||
        controller.status == AnimationStatus.reverse ||
        dragHeight <= 0) {
      return;
    }
    final delta = details.primaryDelta ?? 0;
    controller.value = (controller.value - delta / dragHeight).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details, double dragHeight) {
    final controller = this.controller;
    if (controller == null || controller.status == AnimationStatus.reverse) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final draggedFraction = 1 - controller.value;
    final shouldDismiss =
        draggedFraction >= BmMotion.sheetDismissFraction ||
        velocity > BmMotion.sheetDismissVelocity;
    // 不可关闭的 Sheet 只允许弹回，拖拽不能绕过 barrierDismissible。
    if (barrierDismissible && shouldDismiss) {
      if (isCurrent) navigator?.pop();
      return;
    }
    if (reduceMotion) {
      controller.value = 1;
      return;
    }
    controller.animateWith(
      SpringSimulation(
        BmMotion.sheetSpring,
        controller.value,
        1,
        -velocity / dragHeight,
      ),
    );
  }

  void _handleDragCancel() {
    final controller = this.controller;
    if (controller == null || controller.status == AnimationStatus.reverse) {
      return;
    }
    if (reduceMotion) {
      controller.value = 1;
      return;
    }
    controller.animateWith(
      SpringSimulation(BmMotion.sheetSpring, controller.value, 1, 0),
    );
  }
}
