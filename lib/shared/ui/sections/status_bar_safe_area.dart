import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/utils/duo_layout.dart';

// iPhone Duo 展开竖拿时，状态栏只占右上角一块，那一行其余的地方给页面的
// 顶栏用（不留空）。位置全部取系统给的数值（[DuoLayout.topBarOf]）：顶栏
// 在这一行里和时间对齐、右侧让开状态栏；内容从这一行下面开始。

/// 标签页正文外层的 [SafeArea]：展开竖拿时不整块让开顶部，页头
/// （[StatusBarHeaderInset]）上移进状态栏那一行。
///
/// 其他设备和姿态下与 [SafeArea] 完全相同。两种情况结构一样，开合时
/// 不丢页面状态。
class StatusBarSafeArea extends StatelessWidget {
  const StatusBarSafeArea({
    super.key,
    this.top = true,
    this.bottom = true,
    this.left = true,
    this.right = true,
    required this.child,
  });

  final bool top;
  final bool bottom;
  final bool left;
  final bool right;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = top ? DuoLayout.topBarOf(context) : null;
    return SafeArea(
      top: top && layout == null,
      bottom: bottom,
      left: left,
      right: right,
      // 用 SafeArea 内层的 context，左右 / 底部已经按上面的参数处理过。
      child: Builder(
        builder: (context) => MediaQuery.removePadding(
          context: context,
          removeTop: layout != null,
          child: TopStatusBarHeaderScope(
            layout: layout,
            contentTop: 0,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 二级页 / 播放详情页外层：展开竖拿时把导航栏放进状态栏那一行。
///
/// 导航栏（[AppBar]）的高度是工具栏高度加顶部安全区。这里把顶部安全区改成
/// 系统给工具栏的顶边，返回键和标题排在时间那一行；右侧按钮通过
/// [AppBarThemeData.actionsPadding] 让开状态栏。自绘页头的页面
/// （[StatusBarSafeArea] / [StatusBarHeaderInset]）按同样的数值处理。
///
/// 其他设备和姿态下不改动任何东西；两种情况结构一样。
class StatusBarToolbarArea extends StatelessWidget {
  const StatusBarToolbarArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = DuoLayout.topBarOf(context);
    final data = MediaQuery.of(context);
    final theme = Theme.of(context);
    return MediaQuery(
      data: layout == null
          ? data
          : data.copyWith(
              padding: data.padding.copyWith(top: layout.toolbarTop),
            ),
      child: Theme(
        data: layout == null
            ? theme
            : theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                  actionsPadding: EdgeInsets.only(right: layout.trailing),
                ),
              ),
        child: TopStatusBarHeaderScope(
          layout: layout,
          contentTop: layout?.toolbarTop ?? 0,
          child: child,
        ),
      ),
    );
  }
}

/// 页头那一行：展开竖拿时按钮行和时间对齐、右侧让开状态栏，并至少铺到
/// 这一行底部，下面的内容不会压到状态栏；其他情况原样返回 [child]。
///
/// 只能放在页面最上面（紧贴 [StatusBarSafeArea] / [StatusBarToolbarArea]
/// 给出的顶边）。[ownTopPadding] / [ownRightPadding] 是 [child] 自身已有的
/// 上 / 右内边距。
class StatusBarHeaderInset extends StatelessWidget {
  const StatusBarHeaderInset({
    super.key,
    this.ownTopPadding = 0,
    this.ownRightPadding = 0,
    required this.child,
  });

  final double ownTopPadding;
  final double ownRightPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = TopStatusBarHeaderScope.maybeOf(context);
    final layout = scope?.layout;
    if (scope == null || layout == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final extra = extraPadding(
          layout: layout,
          contentTop: scope.contentTop,
          outerRightMargin: (screenWidth - constraints.maxWidth) / 2,
          ownTopPadding: ownTopPadding,
          ownRightPadding: ownRightPadding,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, layout.statusBarHeight - scope.contentTop),
          ),
          child: Padding(padding: extra, child: child),
        );
      },
    );
  }

  /// 页头还要补的上 / 右内边距（纯逻辑，便于测试）。
  ///
  /// 上：页头内容的顶边落到系统给按钮行的顶边；右：页头到屏幕右边缘的距离
  /// （外层边距 + 自身右内边距）不够让开状态栏时补足。
  @visibleForTesting
  static EdgeInsets extraPadding({
    required TopBarLayout layout,
    required double contentTop,
    required double outerRightMargin,
    required double ownTopPadding,
    required double ownRightPadding,
  }) {
    return EdgeInsets.only(
      top: math.max(0, layout.rowTop - contentTop - ownTopPadding),
      right: math.max(0, layout.trailing - outerRightMargin - ownRightPadding),
    );
  }
}

/// 状态栏那一块的底色：内容往上滚进这一行底下时，文字不和时间、Wi-Fi
/// 重叠。展开竖拿时由外壳铺在页面上面；其他情况不画。
class StatusBarBacking extends StatelessWidget {
  const StatusBarBacking({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = DuoLayout.topBarOf(context);
    if (layout == null) return const SizedBox.shrink();
    final rect = layout.statusRect;
    final radius = BorderRadius.only(
      bottomLeft: Radius.circular(rect.height / 2),
    );
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: ColoredBox(
              color: context.bmColors.bg.withValues(alpha: 0.86),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标记页面顶部已经上移进状态栏那一行。
class TopStatusBarHeaderScope extends InheritedWidget {
  const TopStatusBarHeaderScope({
    super.key,
    required this.layout,
    required this.contentTop,
    required super.child,
  });

  /// 系统给的顶栏位置；不在展开竖拿时为 null。
  final TopBarLayout? layout;

  /// 页面内容的顶边离屏幕顶边的距离。
  final double contentTop;

  /// 页面顶部上移进了状态栏那一行时返回作用域，否则返回 null。
  static TopStatusBarHeaderScope? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TopStatusBarHeaderScope>();
    return scope?.layout == null ? null : scope;
  }

  @override
  bool updateShouldNotify(TopStatusBarHeaderScope oldWidget) =>
      layout != oldWidget.layout || contentTop != oldWidget.contentTop;
}
