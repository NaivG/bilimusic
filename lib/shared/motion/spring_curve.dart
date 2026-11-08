import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

import 'motion_tokens.dart';

/// 弹簧曲线：前 [seconds] 按弹簧走，剩余残差线性收尾，保证 t=1 时正好为 1。
///
/// 用它替代“固定时长 + Curves.easeOut 假装弹簧”的写法；残差线性收尾避免
/// 动画在末帧跳一下（弹簧在 [seconds] 处通常还没精确收敛到 1）。
class SpringCurve extends Curve {
  SpringCurve(this.spring, {required this.seconds})
    : assert(seconds > 0, 'seconds 必须为正'),
      _simulation = SpringSimulation(spring, 0, 1, 0) {
    _residual = 1 - _simulation.x(seconds);
  }

  final SpringDescription spring;

  /// 弹簧段时长（秒）。
  final double seconds;

  final SpringSimulation _simulation;
  late final double _residual;

  /// 页面 push/pop：临界阻尼，不 overshoot。
  factory SpringCurve.page() => SpringCurve(BmMotion.pageSpring, seconds: 0.3);

  /// Sheet：UIKit presentation spring，500ms 上限。
  factory SpringCurve.sheet() =>
      SpringCurve(BmMotion.sheetSpring, seconds: 0.5);

  /// 按压回弹：按钮 / 封面。
  factory SpringCurve.press() =>
      SpringCurve(BmMotion.pressSpring, seconds: 0.2);

  /// 开关 thumb。
  factory SpringCurve.switchThumb() =>
      SpringCurve(BmMotion.switchSpring, seconds: 0.25);

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}
