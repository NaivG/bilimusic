import 'package:flutter/material.dart';

/// AnimatedSwitcher 专用的防重复 key 过渡构建器。
///
/// AnimatedSwitcher 默认 transitionBuilder 会给 FadeTransition 挂上
/// `ValueKey(child.key)`，而 KeyedSubtree.wrap 会把「builder 产物的 key」
/// （非空时）直接用作过渡条目的顶层 key，导致 `_childNumber` 序号失效：
/// key 固定（或为 null）的分支在淡出窗口期内再次切入时，Stack 会同时出现
/// 两个相同顶层 key 的条目，触发 "Duplicate keys found" 断言
/// （典型 key 形如 `[<[<null>]>]`，常见于 crossfade 指示器快速闪烁、
/// 连点播放/暂停、快速切回同一封面等场景）。
///
/// 这里返回不带 key 的 FadeTransition，让 AnimatedSwitcher 回退到按
/// `_childNumber` 生成的唯一 slot key，从根本上消除重复 key；
/// 渲染效果与默认行为一致。
Widget switcherFadeTransition(Widget child, Animation<double> animation) {
  return FadeTransition(opacity: animation, child: child);
}

/// 通用淡入动画组件
class FadeInWidget extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  const FadeInWidget({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOut,
  });

  @override
  State<FadeInWidget> createState() => _FadeInWidgetState();
}

class _FadeInWidgetState extends State<FadeInWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

/// 通用缩放动画组件（支持悬停效果）
class ScaleOnHover extends StatefulWidget {
  final Widget child;
  final double hoverScale;
  final double normalScale;
  final Duration duration;
  final bool enableHover;

  const ScaleOnHover({
    super.key,
    required this.child,
    this.hoverScale = 1.02,
    this.normalScale = 1.0,
    this.duration = const Duration(milliseconds: 200),
    this.enableHover = true,
  });

  @override
  State<ScaleOnHover> createState() => _ScaleOnHoverState();
}

class _ScaleOnHoverState extends State<ScaleOnHover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enableHover
          ? (_) => setState(() => _isHovered = true)
          : null,
      onExit: widget.enableHover
          ? (_) => setState(() => _isHovered = false)
          : null,
      child: AnimatedScale(
        scale: _isHovered ? widget.hoverScale : widget.normalScale,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 点击缩放动画组件
class TapScaleWidget extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final Duration duration;
  final VoidCallback? onTap;

  const TapScaleWidget({
    super.key,
    required this.child,
    this.pressedScale = 0.98,
    this.duration = const Duration(milliseconds: 100),
    this.onTap,
  });

  @override
  State<TapScaleWidget> createState() => _TapScaleWidgetState();
}

class _TapScaleWidgetState extends State<TapScaleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
