import 'package:flutter/material.dart';

/// Lucent 几何 / 尺寸 token。
///
/// 与主题无关：6 套主题 × 深浅共用同一份 const，随主题变化的只有
/// [BmColors]。组件统一通过 `context.bm` 读取；主题未注入时回退
/// [BmTokens.standard]，保证测试与早期 build 阶段不抛异常。
@immutable
class BmTokens extends ThemeExtension<BmTokens> {
  const BmTokens();

  static const BmTokens standard = BmTokens();

  // ===== Radius（6 档）=====
  static const double r4 = 4;
  static const double r10 = 10;
  static const double r14 = 14;
  static const double r20 = 20;
  static const double r28 = 28;
  static const double rPill = 999;

  static const BorderRadius r4All = BorderRadius.all(Radius.circular(r4));
  static const BorderRadius r10All = BorderRadius.all(Radius.circular(r10));
  static const BorderRadius r14All = BorderRadius.all(Radius.circular(r14));
  static const BorderRadius r20All = BorderRadius.all(Radius.circular(r20));
  static const BorderRadius r28All = BorderRadius.all(Radius.circular(r28));
  static const BorderRadius rPillAll = BorderRadius.all(Radius.circular(rPill));

  // ===== Spacing（7 档）=====
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // ===== 行高 =====
  static const double rowCompact = 40;
  static const double row = 48;
  static const double rowTall = 56;

  // ===== 控件高 =====
  static const double controlSm = 28;
  static const double controlMd = 34;
  static const double controlLg = 40;

  // ===== 图标（只允许这 4 档）=====
  static const double iconInline = 14;
  static const double iconMenu = 16;
  static const double icon = 20;
  static const double iconLarge = 24;

  // ===== Chrome 浮层（菜单 / 对话框 / Sheet）=====
  /// 菜单行高（设计文档 §4.6）。
  static const double menuRow = 32;

  /// 菜单浮层内边距（设计文档 §4.6）。
  static const double menuInset = 6;

  // ===== 触摸区下限 =====
  static const double touchDesktop = 40;
  static const double touchScreen = 44;

  // ===== 常用内边距 =====
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: s4);
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: s4,
    vertical: s2,
  );

  /// 取当前主题注入的 token；未注入时回退 [standard]。
  static BmTokens of(BuildContext context) =>
      Theme.of(context).extension<BmTokens>() ?? standard;

  @override
  BmTokens copyWith() => this;

  @override
  BmTokens lerp(ThemeExtension<BmTokens>? other, double t) => this;
}

extension BmTokensContext on BuildContext {
  BmTokens get bm => BmTokens.of(this);
}
