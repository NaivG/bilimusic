import 'package:flutter/material.dart';

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

/// 交错动画列表组件
class StaggeredList extends StatelessWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;
  final Axis axis;

  const StaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 50),
    this.itemDuration = const Duration(milliseconds: 300),
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    return axis == Axis.vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildChildren(),
          )
        : Row(children: _buildChildren());
  }

  List<Widget> _buildChildren() {
    final result = <Widget>[];
    Duration currentDelay = Duration.zero;

    for (int i = 0; i < children.length; i++) {
      result.add(
        FadeInWidget(
          delay: currentDelay,
          duration: itemDuration,
          child: children[i],
        ),
      );
      currentDelay += itemDelay;
    }

    return result;
  }
}

/// 渐变遮罩组件
class GradientOverlay extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;
  final double opacity;

  const GradientOverlay({
    super.key,
    required this.child,
    this.colors = const [Colors.transparent, Colors.black],
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.opacity = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: begin,
                  end: end,
                  colors: colors
                      .map((c) => c.withValues(alpha: opacity))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
