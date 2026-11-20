import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

import 'motion_tokens.dart';

/// 弹簧曲线：前 [seconds] 按弹簧走，剩余残差线性收尾，保证 t=1 时正好为 1。
///
/// 用它替代“固定时长 + Curves.easeOut 假装弹簧”的写法；残差线性收尾避免
/// 动画在末帧跳一下（弹簧在 [seconds] 处通常还没精确收敛到 1）。
class SpringCurve extends Curve {
  SpringCurve(this.spring, {required this.seconds, this.initialVelocity = 0})
    : assert(seconds > 0, 'seconds 必须为正'),
      _simulation = SpringSimulation(spring, 0, 1, initialVelocity) {
    _residual = 1 - _simulation.x(seconds);
  }

  final SpringDescription spring;

  /// 弹簧段时长（秒）。
  final double seconds;

  /// 弹簧段初速（整段距离/秒，1.0 = 一秒走完全程）。
  ///
  /// 页面 push/pop 用 [BmMotion.pageInitialVelocityFactor]（9 × 距离/秒），
  /// 让新页进场是「快速起步 + 缓收」，而不是从静止加速。
  final double initialVelocity;

  final SpringSimulation _simulation;
  late final double _residual;

  /// 页面 push/pop：临界阻尼、初速 9 × 距离/秒、固定 [BmMotion.pageMax] 窗口。
  factory SpringCurve.page() => SpringCurve(
    BmMotion.pageSpring,
    seconds: BmMotion.pageMax.inMicroseconds / Duration.microsecondsPerSecond,
    initialVelocity: BmMotion.pageInitialVelocityFactor,
  );

  /// Sheet：UIKit presentation spring，500ms 上限。
  factory SpringCurve.sheet() =>
      SpringCurve(BmMotion.sheetSpring, seconds: 0.5);

  /// 按压回弹：按钮 / 封面。
  factory SpringCurve.press() =>
      SpringCurve(BmMotion.pressSpring, seconds: 0.2);

  /// 开关 thumb。
  factory SpringCurve.switchThumb() =>
      SpringCurve(BmMotion.switchSpring, seconds: 0.25);

  /// 歌词滚动：普通播放的纵向弹簧。
  factory SpringCurve.lyricScroll() => SpringCurve(
    BmMotion.lyricScrollSpring,
    seconds:
        BmMotion.lyricScrollMax.inMicroseconds / Duration.microsecondsPerSecond,
  );

  /// 歌词行切换：行缩放弹簧。
  factory SpringCurve.lyricLine() => SpringCurve(
    BmMotion.lyricScaleSpring,
    seconds:
        BmMotion.lyricSwitchMax.inMicroseconds / Duration.microsecondsPerSecond,
  );

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}
