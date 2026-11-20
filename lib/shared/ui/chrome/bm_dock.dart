import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 胶囊横移时最多拉伸的比例。
const double _lensStretch = 0.12;

/// 胶囊刹停时最多压缩的比例。
const double _lensBrake = 0.06;

/// 拉伸达到上限时的速度（项 / 秒）。
const double _lensStretchSpeed = 2.5;

/// 压缩达到上限时的减速度（项 / 秒²）。
const double _lensBrakeSpeed = 40;

/// 胶囊纵向压缩与横向拉伸的比例。
const double _lensSquash = 0.6;

/// 把 [value] 平滑压进 0–1，用来让果冻形变快速饱和、缓慢回落。
double _saturate(double value) => 1 - 2 / (math.exp(2 * value) + 1);

/// 浮动 Dock 的一项。
class BmDockItem {
  const BmDockItem({required this.icon, required this.label, this.activeIcon});

  /// 未选中时的图标。
  final IconData icon;

  /// 底栏文案。
  final String label;

  /// 选中时替换的图标；为空时沿用 [icon]。
  final IconData? activeIcon;
}

/// 竖屏浮动 Dock。
///
/// 60 高、左右 12、底 38、30 圆角；白底 82% + 模糊。选中胶囊在项间弹簧
/// 横移，悬停时滑到指针下的项并向光标方向轻微前倾（iOS tab bar /
/// prism_ui `NavigationDock`）；选中项是 `accent @ 18%` 胶囊，悬停预览时
/// 淡到 `accent @ 11%`。由壳层 `Positioned` 挂载，不占
/// `Scaffold.bottomNavigationBar` 的布局位。
class BmDock extends StatefulWidget {
  const BmDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.blur = true,
  });

  final List<BmDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 是否启用背景模糊，直接透传给 [BmChromeSurface]。
  final bool blur;

  /// Dock 占位高度（含上下安全间距的一半，供页面底部预算参考）。
  static const double height = BmTokens.dockHeight;
  static const double bottomInset = BmTokens.dockBottom;
  static const double sideInset = BmTokens.dockInset;

  /// 滑动胶囊的 Key，供预览页与测试定位。
  static const Key lensKey = ValueKey<String>('bm-dock-lens');

  @override
  State<BmDock> createState() => _BmDockState();
}

class _BmDockState extends State<BmDock> with TickerProviderStateMixin {
  late final _DockSpring _lens;

  /// 指针当前所在的项；为 null 表示指针不在 Dock 上。
  int? _hoveredIndex;

  double get _selectedIndex {
    if (widget.items.isEmpty) return 0;
    return widget.selectedIndex.clamp(0, widget.items.length - 1).toDouble();
  }

  bool get _reduceMotion => reduceMotionOf(context);

  @override
  void initState() {
    super.initState();
    _lens = _DockSpring(this, _selectedIndex);
  }

  @override
  void didUpdateWidget(covariant BmDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) {
      _hoveredIndex = null;
      return;
    }
    if (_hoveredIndex != null && _hoveredIndex! >= widget.items.length) {
      _hoveredIndex = null;
    }
    final selectionChanged = oldWidget.selectedIndex != widget.selectedIndex;
    final itemsChanged = oldWidget.items.length != widget.items.length;
    if ((selectionChanged || itemsChanged) && _hoveredIndex == null) {
      _animateTo(_selectedIndex, BmMotion.dockTravelSpring);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    super.dispose();
  }

  void _animateTo(double target, SpringDescription spring) {
    if (_reduceMotion) {
      _lens.jumpTo(target);
    } else {
      _lens.springTo(target, spring);
    }
  }

  /// 指针位置换算成「第几项 + 项内偏移」，再压成悬停倾斜后的目标位置。
  void _handleHover(PointerHoverEvent event) {
    final count = widget.items.length;
    if (count == 0) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.width <= 0) return;
    final width = box.size.width;
    final pitch = width / count;
    final dx = Directionality.of(context) == TextDirection.rtl
        ? width - event.localPosition.dx
        : event.localPosition.dx;
    final raw = (dx / pitch - 0.5).clamp(0.0, count - 1.0);
    final index = raw.round().clamp(0, count - 1);
    if (_hoveredIndex != index) {
      setState(() => _hoveredIndex = index);
    }
    final last = (count - 1).toDouble();
    final leaned = (index + (raw - index) * BmMotion.dockHoverLean).clamp(
      0.0,
      last,
    );
    _animateTo(leaned, BmMotion.dockFollowSpring);
  }

  void _handleExit(PointerExitEvent event) {
    if (_hoveredIndex == null) return;
    setState(() => _hoveredIndex = null);
    _animateTo(_selectedIndex, BmMotion.dockTravelSpring);
  }

  /// 胶囊的果冻形变：横移速度越大越拉长，减速时反向压扁。
  double _stretchOf() {
    if (_reduceMotion) return 0;
    final velocity = _lens.velocity;
    final braking = math.max(0.0, -_lens.acceleration * velocity.sign);
    return _lensStretch * _saturate(velocity.abs() / _lensStretchSpeed) -
        _lensBrake * _saturate(braking / _lensBrakeSpeed);
  }

  @override
  Widget build(BuildContext context) {
    return BmChromeSurface(
      floating: true,
      tone: BmChromeTone.raised,
      radius: BmTokens.dockRadius,
      blur: widget.blur,
      child: SizedBox(
        height: BmTokens.dockHeight,
        child: widget.items.isEmpty
            ? const SizedBox.shrink()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final pitch = width / widget.items.length;
                  final lensWidth = math.min(BmTokens.dockItemWidth, pitch);
                  final preview =
                      _hoveredIndex != null &&
                      _hoveredIndex != widget.selectedIndex;
                  return MouseRegion(
                    onHover: _handleHover,
                    onExit: _handleExit,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _lens,
                                builder: (context, _) => _DockLens(
                                  position: _lens.value,
                                  pitch: pitch,
                                  dockWidth: width,
                                  lensWidth: lensWidth,
                                  preview: preview,
                                  stretch: _stretchOf(),
                                  textDirection: Directionality.of(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (
                              var index = 0;
                              index < widget.items.length;
                              index++
                            )
                              Expanded(
                                child: _BmDockItemView(
                                  item: widget.items[index],
                                  selected: index == widget.selectedIndex,
                                  hovered: index == _hoveredIndex,
                                  width: lensWidth,
                                  onTap: () => widget.onSelected(index),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 选中 / 悬停预览共用的滑动胶囊。
///
/// 位置以「项」为单位，`0` 是第一项中心；横向拉伸、纵向压缩由 [stretch]
/// 控制，形变只影响绘制，不参与布局与命中测试。
class _DockLens extends StatelessWidget {
  const _DockLens({
    required this.position,
    required this.pitch,
    required this.dockWidth,
    required this.lensWidth,
    required this.preview,
    required this.stretch,
    required this.textDirection,
  });

  final double position;
  final double pitch;
  final double dockWidth;
  final double lensWidth;
  final bool preview;
  final double stretch;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final centerX = (position + 0.5) * pitch;
    final visualCenterX = textDirection == TextDirection.rtl
        ? dockWidth - centerX
        : centerX;
    final travel = math.max(0.0, dockWidth - lensWidth);
    final alignmentX = travel == 0
        ? -1.0
        : ((visualCenterX - lensWidth / 2) / travel * 2 - 1).clamp(-1.0, 1.0);
    return Align(
      alignment: Alignment(alignmentX, 0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          1 + stretch,
          1 - stretch * _lensSquash,
          1,
        ),
        child: AnimatedContainer(
          key: BmDock.lensKey,
          width: lensWidth,
          height: BmTokens.dockItemHeightActive,
          duration: motionDuration(context, BmMotion.medium),
          curve: BmMotion.standard,
          decoration: BoxDecoration(
            color: preview ? colors.accentSoft : colors.accentSoftStrong,
            borderRadius: BmTokens.dockItemRadiusAll,
          ),
        ),
      ),
    );
  }
}

/// 单个 Dock 项：图标 + 文案；胶囊状态层由 [BmDock] 统一绘制。
class _BmDockItemView extends StatelessWidget {
  const _BmDockItemView({
    required this.item,
    required this.selected,
    required this.hovered,
    required this.width,
    required this.onTap,
  });

  final BmDockItem item;
  final bool selected;
  final bool hovered;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final icon = selected ? (item.activeIcon ?? item.icon) : item.icon;
    final tint = selected
        ? colors.accentDeep
        : (hovered ? colors.textPrimary : colors.textSecondary);
    final duration = motionDuration(context, BmMotion.small);

    return Center(
      child: SizedBox(
        width: width,
        height: BmTokens.dockItemHeight,
        child: BmPressable(
          onTap: onTap,
          selected: selected,
          // 状态层交给整颗滑动胶囊，按钮只保留语义、焦点环与按压缩放。
          overlayColor: Colors.transparent,
          pressScale: 0.96,
          borderRadius: BmTokens.dockItemRadiusAll,
          semanticLabel: item.label,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: tint),
            duration: duration,
            curve: BmMotion.standard,
            builder: (context, color, _) {
              final itemColor = color ?? tint;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: BmTokens.navIcon, color: itemColor),
                  const SizedBox(height: 1),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.micro.copyWith(
                      color: itemColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 会重定向目标的弹簧值：指针每帧都可能改目标，因此不用
/// `AnimationController.animateWith`（重启 ticker 会丢掉速度）。
class _DockSpring extends ChangeNotifier {
  _DockSpring(TickerProvider vsync, double value)
    : _value = value,
      _target = value {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _value;
  double _target;
  double _now = 0;
  double _start = 0;
  SpringSimulation? _simulation;
  SpringDescription? _spring;

  double get value => _value;

  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  double get acceleration {
    final simulation = _simulation;
    final spring = _spring;
    if (simulation == null || spring == null) return 0;
    return (spring.stiffness * (_target - _value) - spring.damping * velocity) /
        spring.mass;
  }

  void springTo(double target, SpringDescription spring) {
    if (_simulation != null && target == _target) return;
    _simulation = SpringSimulation(
      spring,
      _value,
      target,
      velocity,
      tolerance: const Tolerance(distance: 1e-3, velocity: 1e-2),
    );
    _spring = spring;
    _target = target;
    if (_ticker.isActive) {
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  void jumpTo(double value) {
    _simulation = null;
    _spring = null;
    _ticker.stop();
    _target = value;
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation;
    if (simulation == null) {
      _ticker.stop();
      return;
    }
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target;
      _simulation = null;
    } else {
      _value = simulation.x(time);
    }
    if (_simulation == null) _ticker.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
