import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 菜单入场方式。
enum BmMenuEntranceKind {
  /// 从锚点方向缩放 + 淡入。
  scale,

  /// 水平位移 + 淡入（子菜单）。
  submenu,
}

/// Lucent 菜单浮层。
///
/// `floating` 底 + 0.5 hairline 边 + `shadow` 投影 + 14 圆角，垂直内边距
/// [BmTokens.menuInset]；`entrance` 非空时外层再包 [BmMenuEntrance]。
///
/// ```dart
/// BmMenuSurface(
///   entrance: BmMenuEntranceKind.scale,
///   child: Column(children: rows),
/// )
/// ```
class BmMenuSurface extends StatelessWidget {
  const BmMenuSurface({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth = 450,
    this.entrance,
    this.alignment,
  });

  final Widget child;

  /// 内容内边距，默认上下 [BmTokens.menuInset]。
  final EdgeInsetsGeometry? padding;

  /// 浮层最大宽度。
  final double maxWidth;

  /// 入场动画；为 null 时不做入场（移动端由库自己的转场驱动）。
  final BmMenuEntranceKind? entrance;

  /// 缩放入场锚点，默认 [Alignment.topLeft]。
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final Widget surface = Container(
      decoration: BoxDecoration(
        color: colors.floating,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            offset: const Offset(0, BmTokens.s1),
            blurRadius: BmTokens.s4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BmTokens.r14All,
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(vertical: BmTokens.menuInset),
          child: DefaultTextStyle(
            style: type.body.copyWith(color: colors.textPrimary),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
    final entrance = this.entrance;
    if (entrance == null) return surface;
    return BmMenuEntrance(kind: entrance, alignment: alignment, child: surface);
  }
}

/// 菜单入场动画。
///
/// [kind] 为 [BmMenuEntranceKind.scale] 时从 0.96 缩放到 1，为
/// [BmMenuEntranceKind.submenu] 时水平位移 8px；两者都叠加淡入。时长
/// [BmMotion.small]、曲线 [BmMotion.emphasized]；reduce motion 下直接终态。
///
/// 只在首次挂载时播一次：桌面 builder 的 `buildMenuContainer` 会随焦点变化
/// 反复重建，控制器不能建在 build 里。
class BmMenuEntrance extends StatefulWidget {
  const BmMenuEntrance({
    super.key,
    required this.child,
    this.kind = BmMenuEntranceKind.scale,
    this.alignment,
  });

  final Widget child;
  final BmMenuEntranceKind kind;

  /// 缩放锚点，默认 [Alignment.topLeft]。
  final AlignmentGeometry? alignment;

  @override
  State<BmMenuEntrance> createState() => _BmMenuEntranceState();
}

class _BmMenuEntranceState extends State<BmMenuEntrance>
    with SingleTickerProviderStateMixin {
  static const double _scaleBegin = 0.96;

  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: BmMotion.small);
    _curve = CurvedAnimation(parent: _controller, curve: BmMotion.emphasized);
  }

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
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) return widget.child;
    final alignment = widget.alignment ?? Alignment.topLeft;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final value = _curve.value;
        Widget content = Opacity(opacity: value, child: child);
        if (widget.kind == BmMenuEntranceKind.scale) {
          content = Transform.scale(
            scale: _scaleBegin + (1 - _scaleBegin) * value,
            alignment: alignment,
            child: content,
          );
        } else {
          content = Transform.translate(
            offset: Offset(-BmTokens.s2 * (1 - value), 0),
            child: content,
          );
        }
        return content;
      },
      child: widget.child,
    );
  }
}
