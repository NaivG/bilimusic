import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

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
    return SafeArea(
      child: AnimatedPadding(
        padding: MediaQuery.viewInsetsOf(context),
        duration: reduceMotion ? Duration.zero : BmMotion.medium,
        curve: BmMotion.standard,
        child: Center(
          child: Theme(
            data: theme,
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = animation.drive(CurveTween(curve: BmMotion.emphasized));
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: child,
      ),
    );
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

/// 单选浮层菜单路由。
///
/// 面板在锚点下方（放不下时翻到上方）按锚点右缘对齐；进场 120ms
/// scale 0.96→1 + fade，缩放锚点是面板贴近锚点的那个角；退场同样 120ms。
/// [reduceMotion] 下只保留透明度过渡。
///
/// 路由本身只负责定位与转场，面板内容由 [builder] 提供。
class BmSelectMenuRoute<T> extends PopupRoute<T> {
  BmSelectMenuRoute({
    required this.builder,
    required this.theme,
    required this.anchorRect,
    required this.opensUp,
    required this.width,
    required this.maxHeightFactor,
    required this.barrierLabel,
    this.barrierDismissible = true,
    this.reduceMotion = false,
    super.settings,
  });

  /// 面板内容。
  final WidgetBuilder builder;

  /// 调用点当时的主题，在浮层里原样注入。
  final ThemeData theme;

  /// 锚点控件的全局矩形。
  final Rect anchorRect;

  /// 估算出的方向：菜单更高时优先向上翻。
  final bool opensUp;

  /// 面板宽度；null 时取 [BmTokens.selectMenuWidth]。
  final double? width;

  /// 面板最大高度占屏幕高度的比例。
  final double maxHeightFactor;

  @override
  final String? barrierLabel;

  @override
  final bool barrierDismissible;

  /// reduce motion 下只保留透明度过渡。
  final bool reduceMotion;

  /// 锚定浮层不压暗背景：透明的 ModalBarrier 只负责点外关闭。
  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => BmMotion.small;

  @override
  Duration get reverseTransitionDuration => BmMotion.small;

  @override
  Curve get barrierCurve => BmMotion.linear;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final direction = Directionality.of(context);

    final panel = Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (isCurrent) navigator?.maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Theme(
        data: theme,
        child: Builder(builder: builder),
      ),
    );

    final Widget animatedPanel;
    if (reduceMotion) {
      animatedPanel = FadeTransition(opacity: animation, child: panel);
    } else {
      final curved = animation.drive(CurveTween(curve: BmMotion.emphasized));
      animatedPanel = FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: _selectMenuAlignment(direction, opensUp),
          child: panel,
        ),
      );
    }

    return CustomSingleChildLayout(
      delegate: _BmSelectMenuLayout(
        anchorRect: anchorRect,
        opensUp: opensUp,
        width: width,
        maxHeightFactor: maxHeightFactor,
        direction: direction,
        padding: media.padding,
      ),
      child: SizedBox(width: double.infinity, child: animatedPanel),
    );
  }

  /// 转场与定位都在 [buildPage] 里完成：缩放必须围绕面板自己的角，
  /// 而不是整页的角，否则面板会随整页缩放产生位移。
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// 面板相对锚点的定位：优先下方，下方放不下时翻到上方。
class _BmSelectMenuLayout extends SingleChildLayoutDelegate {
  _BmSelectMenuLayout({
    required this.anchorRect,
    required this.opensUp,
    required this.width,
    required this.maxHeightFactor,
    required this.direction,
    required this.padding,
  });

  static const double _gap = BmTokens.s1;
  static const double _margin = BmTokens.s2;

  final Rect anchorRect;
  final bool opensUp;
  final double? width;
  final double maxHeightFactor;
  final TextDirection direction;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final safeWidth = constraints.maxWidth - padding.horizontal - _margin * 2;
    final safeHeight = constraints.maxHeight - padding.vertical - _margin * 2;
    final maxWidth = math.max(
      1.0,
      math.min(width ?? BmTokens.selectMenuWidth, safeWidth),
    );
    final safeTop = padding.top + _margin;
    final safeBottom = constraints.maxHeight - padding.bottom - _margin;
    final spaceBelow = math.max(0.0, safeBottom - (anchorRect.bottom + _gap));
    final spaceAbove = math.max(0.0, anchorRect.top - _gap - safeTop);
    final available = math.max(spaceAbove, spaceBelow);
    final maxHeight = math.max(
      1.0,
      math.min(
        math.min(safeHeight, constraints.maxHeight * maxHeightFactor),
        math.min(
          BmTokens.selectMenuMaxHeight,
          available == 0 ? BmTokens.touchScreen : available,
        ),
      ),
    );
    return BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final safeTop = padding.top + _margin;
    final safeBottom = size.height - padding.bottom - _margin;
    final safeLeft = padding.left + _margin;
    final safeRight = size.width - padding.right - _margin;
    final spaceBelow = math.max(0.0, safeBottom - (anchorRect.bottom + _gap));
    final spaceAbove = math.max(0.0, anchorRect.top - _gap - safeTop);
    final belowFits = spaceBelow >= childSize.height;
    final aboveFits = spaceAbove >= childSize.height;
    final bool up;
    if (belowFits && aboveFits) {
      up = opensUp;
    } else if (belowFits) {
      up = false;
    } else if (aboveFits) {
      up = true;
    } else {
      up = spaceAbove > spaceBelow;
    }
    final rawTop = up
        ? anchorRect.top - _gap - childSize.height
        : anchorRect.bottom + _gap;
    final top = _clamp(rawTop, safeTop, safeBottom - childSize.height);
    final anchorEdge = direction == TextDirection.rtl
        ? anchorRect.left
        : anchorRect.right;
    final rawLeft = direction == TextDirection.rtl
        ? anchorEdge
        : anchorEdge - childSize.width;
    final left = _clamp(rawLeft, safeLeft, safeRight - childSize.width);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _BmSelectMenuLayout oldDelegate) {
    return anchorRect != oldDelegate.anchorRect ||
        opensUp != oldDelegate.opensUp ||
        width != oldDelegate.width ||
        maxHeightFactor != oldDelegate.maxHeightFactor ||
        direction != oldDelegate.direction ||
        padding != oldDelegate.padding;
  }

  static double _clamp(double value, double lower, double upper) {
    if (upper < lower) return lower;
    return value.clamp(lower, upper).toDouble();
  }
}

/// 缩放锚点：贴着锚点的那条边保持不动。
Alignment _selectMenuAlignment(TextDirection direction, bool opensUp) {
  return Alignment(direction == TextDirection.rtl ? -1 : 1, opensUp ? 1 : -1);
}
