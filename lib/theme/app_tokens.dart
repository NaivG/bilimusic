import 'package:flutter/animation.dart';

/// 跨主题共享的结构性 design tokens。
/// 颜色相关的 token 集中在 [AppPalette],这里只放与主题无关的几何/动效/模糊常量。
abstract class AppTokens {
  // ===== Radius =====
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;

  // ===== Motion =====
  static const Curve standardEasing = Curves.easeOut;
  static const Curve decelerateEasing = Curves.easeIn;
  static const Curve accelerateEasing = Curves.easeOut;
  static const Duration microDuration = Duration(milliseconds: 100);
  static const Duration standardDuration = Duration(milliseconds: 200);
  static const Duration layoutDuration = Duration(milliseconds: 350);

  // ===== Glass / Blur Sigma =====
  static const double glassBlurSigma = 20.0;
  static const double overlayBlurSigma = 24.0;
  static const double heavyGlassBlurSigma = 50.0;
}
