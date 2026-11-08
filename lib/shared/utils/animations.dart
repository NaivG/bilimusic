import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';

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

/// 通用淡入动画组件（淡入 + 8px 上移）。
///
/// 延迟用可取消的 [Timer]，dispose 时随控制器一起停；reduce motion 下
/// 直接落到终态，不再播放入场。
class FadeInWidget extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  const FadeInWidget({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = BmMotion.large,
    this.curve = BmMotion.standard,
  });

  @override
  State<FadeInWidget> createState() => _FadeInWidgetState();
}

class _FadeInWidgetState extends State<FadeInWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _delayTimer;
  bool _started = false;

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

    if (widget.delay == Duration.zero) {
      _start();
    } else {
      _delayTimer = Timer(widget.delay, _start);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && reduceMotionOf(context)) {
      _delayTimer?.cancel();
      _started = true;
      _controller.value = 1;
    }
  }

  void _start() {
    _delayTimer = null;
    if (!mounted || _started) return;
    _started = true;
    _controller.forward();
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
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

/// 通用缩放动画组件（支持悬停放大）。
///
/// 只做「鼠标悬停微放大」这一件事；按压/焦点/选中态请用 `BmPressable`。
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
    this.duration = BmMotion.small,
    this.enableHover = true,
  });

  @override
  State<ScaleOnHover> createState() => _ScaleOnHoverState();
}

class _ScaleOnHoverState extends State<ScaleOnHover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enableHover = widget.enableHover && !reduceMotionOf(context);
    return MouseRegion(
      onEnter: enableHover ? (_) => setState(() => _isHovered = true) : null,
      onExit: enableHover ? (_) => setState(() => _isHovered = false) : null,
      child: AnimatedScale(
        scale: _isHovered ? widget.hoverScale : widget.normalScale,
        duration: enableHover ? widget.duration : Duration.zero,
        curve: BmMotion.standard,
        child: widget.child,
      ),
    );
  }
}
