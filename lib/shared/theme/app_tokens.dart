/// 跨主题共享的结构性 design tokens。
///
/// 这里是**迁移期的存量几何常量**（radius / blur sigma）
/// 新代码请用：
/// - 几何/尺寸：`BmTokens`（`lib/shared/ui/tokens/bm_tokens.dart`）
/// - 动效：`BmMotion`（`lib/shared/motion/motion_tokens.dart`）
/// - 颜色：`BmColors`（`lib/shared/ui/tokens/bm_colors.dart`）
abstract class AppTokens {
  // ===== Radius =====
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;

  // ===== Glass / Blur Sigma =====
  static const double glassBlurSigma = 20.0;
  static const double overlayBlurSigma = 24.0;
  static const double heavyGlassBlurSigma = 50.0;
}
