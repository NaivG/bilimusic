import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Lucent 动效 token：7 档时长 + 4 条曲线 + 4 个弹簧。
///
/// 规则（详见 `docs/lucent-motion.md`）：
/// - 进场 240–320ms、退场 120–240ms；退场永远比进场快。
/// - 超过 320ms 的只有 [hero]（封面形变）、[backdrop]（背景 crossfade）
///   与 [sheetMax]（弹簧收敛上限，不是固定时长）。
/// - 空间移动用弹簧（[pageSpring] / [sheetSpring]），不要用固定时长假装弹簧。
abstract class BmMotion {
  // ===== 时长 =====
  /// 文本选择、滚动、输入法。
  static const Duration instant = Duration.zero;

  /// hover / pressed 状态层进入。
  static const Duration micro = Duration(milliseconds: 80);

  /// 菜单、tooltip、图标交换、focus ring。
  static const Duration small = Duration(milliseconds: 120);

  /// 对话框、toast、chip、颜色过渡。
  static const Duration medium = Duration(milliseconds: 180);

  /// 列表进出、展开/折叠、tab 切换。
  static const Duration large = Duration(milliseconds: 240);

  /// 页面 push/pop、详情内容层。
  static const Duration xlarge = Duration(milliseconds: 320);

  /// 封面 morph（保留既有）。
  static const Duration hero = Duration(milliseconds: 460);

  /// 封面背景 crossfade 的既有例外：大面积颜色变化不按常规档位。
  static const Duration backdrop = Duration(milliseconds: 400);

  /// Sheet 弹簧的最长收敛预算（上限，不是固定时长）。
  static const Duration sheetMax = Duration(milliseconds: 500);

  // ===== 状态层 =====
  /// hover 状态层进入。
  static const Duration hoverIn = micro;

  /// hover 状态层退出（退场比进场快）。
  static const Duration hoverOut = small;

  /// pressed 状态层进入。
  static const Duration pressIn = micro;

  /// pressed 状态层退出。
  static const Duration pressOut = small;

  // ===== 曲线 =====
  /// 进场、位移、展开。
  static const Curve standard = Curves.easeOutCubic;

  /// 退场。
  static const Curve exit = Curves.easeInCubic;

  /// 对话框、菜单、Sheet 内容。
  static const Curve emphasized = Curves.fastOutSlowIn;

  /// 进度、颜色 crossfade。
  static const Curve linear = Curves.linear;

  // ===== 弹簧 =====
  /// 页面 push/pop：临界阻尼，不 overshoot。
  static final SpringDescription pageSpring =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 300),
        bounce: 0,
      );

  /// 页面 push 的初速系数：`9 × 距离 / 秒`。
  static const double pageInitialVelocityFactor = 9;

  /// Sheet：UIKit presentation spring，抛掷时允许轻微 overshoot。
  static final SpringDescription sheetSpring = SpringDescription(
    mass: 3,
    stiffness: 1000,
    damping: _damping(mass: 3, stiffness: 1000, ratio: 0.8),
  );

  /// 按压回弹：只用于按钮 / 封面，不用于列表行。
  static final SpringDescription pressSpring = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: _damping(mass: 1, stiffness: 500, ratio: 0.75),
  );

  /// 开关 thumb：允许 1–2px overshoot。
  static final SpringDescription switchSpring = SpringDescription(
    mass: 1,
    stiffness: 700,
    damping: _damping(mass: 1, stiffness: 700, ratio: 0.85),
  );

  // ===== 编排 =====
  /// 列表 stagger：每项 20ms。
  static const Duration stagger = Duration(milliseconds: 20);

  /// stagger 最多 6 项（上限 120ms），超过就整组一起进。
  static const int staggerMax = 6;

  // ===== 手势 =====
  /// 按压缩放：按钮 / 封面可 0.97，列表行不动。
  static const double pressScale = 0.97;

  /// Sheet 拖拽关闭的速度阈值（px/s）。
  static const double sheetDismissVelocity = 700;

  /// Sheet 拖拽关闭的位移占比阈值。
  static const double sheetDismissFraction = 0.3;

  static double _damping({
    required double mass,
    required double stiffness,
    required double ratio,
  }) {
    return 2 * ratio * math.sqrt(mass * stiffness);
  }
}
