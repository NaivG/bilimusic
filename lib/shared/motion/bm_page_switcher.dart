import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/motion/spring_curve.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';

/// 页面切换类型（见 `docs/lucent-motion.md` §4.1 / §4.2）。
enum BmPageTransitionKind {
  /// 同层切换：微位移 + 双淡，240ms。
  tab,

  /// 进入更深一层：新页从方向侧滑入，旧页退 0.3 并压暗。
  push,

  /// 返回上一层：新页从旧页下方回归，旧页向方向侧滑出。
  pop,

  /// 同层替换：纯淡入淡出，180ms。
  replace,
}

/// 方向化的页面切换容器。
///
/// 壳层在 [pageKey] 变化时把 [kind] / [direction] 一起传进来；组件自己驱动
/// 一次「旧页 → 新页」过渡，结束后只保留新页。与 `AnimatedSwitcher` 不同，
/// 它同时驱动两页的视差与压暗，因此 `push` / `pop` 的层级方向可见。
///
/// 约定：
/// - `direction = +1` 表示进入更深一层（push / tab 下标增大），`-1` 表示返回。
/// - `push` 新页 `Offset(1.0·d, 0)` → 0，旧页 0 → `Offset(-0.3·d, 0)`；
///   `pop` 新页 `Offset(0.3·d, 0)` → 0，旧页 0 → `Offset(-1.0·d, 0)`。
/// - 旧页叠 [BmColors.dim]（15%），不响应指针、不参与语义树。
/// - `push` / `pop` 在 [BmMotion.pageMax]（300ms）窗口内走完：临界阻尼弹簧
///   理论上无限收敛，窗口末段的残差由 [SpringCurve] 线性收尾，旧页随窗口
///   一起出树，不会在动画看起来结束后继续挂着。
/// - 视差是 `FractionalTranslation` 的绘制期位移，`Stack` 的 `clipBehavior`
///   只裁布局溢出；这里必须显式 [ClipRect]，否则被推走的页面会画到页面区域
///   之外（横屏内容区紧贴侧栏时最明显）。
/// - reduce motion 下只保留 ≤120ms 的透明度过渡，不做位移与压暗。
///
/// ```dart
/// BmPageSwitcher(
///   pageKey: manager.basePageKey,
///   kind: manager.lastTransitionKind,
///   direction: manager.lastTransitionDirection,
///   child: page,
/// )
/// ```
class BmPageSwitcher extends StatefulWidget {
  const BmPageSwitcher({
    super.key,
    required this.pageKey,
    required this.child,
    this.kind = BmPageTransitionKind.tab,
    this.direction = 1,
  });

  /// 当前页的 key；变化时触发一次方向化过渡。
  final Key pageKey;

  /// 当前页内容。
  final Widget child;

  /// 本次切换的类型。
  final BmPageTransitionKind kind;

  /// +1 进入更深一层 / -1 返回。
  final int direction;

  @override
  State<BmPageSwitcher> createState() => _BmPageSwitcherState();
}

class _BmPageSwitcherState extends State<BmPageSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late Key _currentKey;
  late Widget _currentChild;
  Key? _previousKey;
  Widget? _previousChild;

  BmPageTransitionKind _kind = BmPageTransitionKind.tab;
  int _direction = 1;
  bool _reduceMotion = false;

  /// 本次过渡的进度曲线；push / pop 用固定窗口的 [SpringCurve]。
  Curve _curve = BmMotion.standard;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BmMotion.large,
      value: 1,
    )..addStatusListener(_onStatus);
    _currentKey = widget.pageKey;
    _currentChild = widget.child;
    _kind = widget.kind;
    _direction = widget.direction;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = reduceMotionOf(context);
  }

  @override
  void didUpdateWidget(covariant BmPageSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageKey == _currentKey) {
      // 同一页的重建：原地换掉 child，保持元素与滚动位置。
      _currentChild = widget.child;
      return;
    }

    // 连续换键时丢弃更早的旧页，只保留最后一对，避免 Stack 里越堆越多。
    _previousKey = _currentKey;
    _previousChild = _currentChild;
    _currentKey = widget.pageKey;
    _currentChild = widget.child;
    _kind = widget.kind;
    _direction = widget.direction;
    _startTransition();
  }

  void _startTransition() {
    if (_previousChild == null) return;
    _controller.stop();

    if (_reduceMotion) {
      _curve = BmMotion.linear;
      _controller.duration = BmMotion.small;
      _controller.forward(from: 0);
      return;
    }

    switch (_kind) {
      case BmPageTransitionKind.push:
      case BmPageTransitionKind.pop:
        // 固定 300ms 窗口：给临界阻尼弹簧一个有限终点，旧页在窗口结束时
        // 立即出树；弹簧末段的残差由 SpringCurve 线性收尾。
        _curve = SpringCurve.page();
        _controller.duration = BmMotion.pageMax;
      case BmPageTransitionKind.tab:
        _curve = BmMotion.standard;
        _controller.duration = BmMotion.large;
      case BmPageTransitionKind.replace:
        _curve = BmMotion.standard;
        _controller.duration = BmMotion.medium;
    }
    _controller.forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    // 弹簧的末值可能停在 1 附近，补齐终态，避免残留 0.01 的视差。
    if (_controller.value != 1) _controller.value = 1;
    if (_previousChild == null) return;
    setState(() {
      _previousChild = null;
      _previousKey = null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;

    // 页面区域自带裁剪：视差是绘制期位移，Stack 只裁布局溢出，不在这里
    // 显式 ClipRect 的话旧页会画到页面区域之外。
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final previous = _previousChild;
          if (previous == null) {
            return Stack(
              key: const Key('bm-page-switcher-stack'),
              fit: StackFit.expand,
              children: [_buildPage(_currentKey, _currentChild)],
            );
          }

          final raw = _controller.value;
          final t = _easedProgress(raw);
          final geometry = _geometry(t);

          final incoming = _buildPage(
            _currentKey,
            _currentChild,
            offset: geometry.incoming,
            opacity: geometry.incomingOpacity,
          );
          final outgoing = _buildPage(
            _previousKey!,
            previous,
            offset: geometry.outgoing,
            opacity: geometry.outgoingOpacity,
            dimOpacity: geometry.dim,
            colors: colors,
          );

          // push/tab 时新页盖在旧页上；pop 时退出的旧页盖在回归页上。
          final children = _kind == BmPageTransitionKind.pop
              ? <Widget>[incoming, outgoing]
              : <Widget>[outgoing, incoming];

          return Stack(
            key: const Key('bm-page-switcher-stack'),
            fit: StackFit.expand,
            children: children,
          );
        },
      ),
    );
  }

  /// push / pop 由 [SpringCurve] 完成缓动；tab / replace 用标准曲线；
  /// reduce motion 下退化为线性淡出。
  double _easedProgress(double raw) => _curve.transform(raw);

  _BmPageGeometry _geometry(double t) {
    final d = _direction.toDouble();
    if (_reduceMotion) {
      return _BmPageGeometry(
        incoming: Offset.zero,
        outgoing: Offset.zero,
        incomingOpacity: t,
        outgoingOpacity: 1 - t,
        dim: 0,
      );
    }

    switch (_kind) {
      case BmPageTransitionKind.tab:
        return _BmPageGeometry(
          incoming: Offset(0.04 * d * (1 - t), 0),
          outgoing: Offset(-0.02 * d * t, 0),
          incomingOpacity: t,
          outgoingOpacity: 1 - t,
          dim: 0,
        );
      case BmPageTransitionKind.push:
        return _BmPageGeometry(
          incoming: Offset(d * (1 - t), 0),
          outgoing: Offset(-0.3 * d * t, 0),
          incomingOpacity: 1,
          outgoingOpacity: 1,
          dim: t,
        );
      case BmPageTransitionKind.pop:
        return _BmPageGeometry(
          incoming: Offset(0.3 * d * (1 - t), 0),
          outgoing: Offset(-d * t, 0),
          incomingOpacity: 1,
          outgoingOpacity: 1,
          dim: t,
        );
      case BmPageTransitionKind.replace:
        return _BmPageGeometry(
          incoming: Offset.zero,
          outgoing: Offset.zero,
          incomingOpacity: t,
          outgoingOpacity: 1 - t,
          dim: 0,
        );
    }
  }

  Widget _buildPage(
    Key key,
    Widget child, {
    Offset offset = Offset.zero,
    double opacity = 1,
    double dimOpacity = 0,
    BmColors? colors,
  }) {
    Widget content = child;
    if (dimOpacity > 0 && colors != null) {
      final overlay = colors.dim.withValues(alpha: colors.dim.a * dimOpacity);
      content = Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: overlay)),
          ),
        ],
      );
    }
    if (opacity < 1) {
      content = Opacity(opacity: opacity, child: content);
    }

    final isCurrent = key == _currentKey;
    if (!isCurrent) {
      content = ExcludeSemantics(child: IgnorePointer(child: content));
    }

    return KeyedSubtree(
      key: key,
      child: FractionalTranslation(translation: offset, child: content),
    );
  }
}

/// 一次过渡的几何参数（偏移按页面宽高归一）。
class _BmPageGeometry {
  const _BmPageGeometry({
    required this.incoming,
    required this.outgoing,
    required this.incomingOpacity,
    required this.outgoingOpacity,
    required this.dim,
  });

  final Offset incoming;
  final Offset outgoing;
  final double incomingOpacity;
  final double outgoingOpacity;
  final double dim;
}
