import 'package:bilimusic/shared/utils/version_compare.dart';

/// 启动时引导页要做什么。
enum OnboardingLaunch {
  /// 不打扰：版本没变，或者是降级。
  none,

  /// 初次启动（盘上没有 `last_boot_version`）：看完整引导。
  onboarding,

  /// 从旧版本升上来：弹「已升级至 x.y.z」，给一个更新日志入口。
  upgradeDialog,
}

/// 根据「当前版本」和「上次启动版本」决定启动行为。
///
/// - 没有历史版本（新装，或第一次运行带这个标记的版本）→ 完整引导。
///   `last_boot_version` 是随引导页一起引入的，所以第一次上线时老用户也
///   没有这个键，会和真正的新用户一样看到一次引导——这正是要的行为。
/// - 版本相同 → 什么都不做。
/// - 版本变大 → 升级弹窗；引导页只负责第一次，后续版本不再重写页面。
/// - 版本变小（降级）→ 不打扰。
OnboardingLaunch decideOnboardingLaunch({
  required String currentVersion,
  required String? lastBootVersion,
}) {
  final current = currentVersion.trim();
  final last = lastBootVersion?.trim();
  if (last == null || last.isEmpty) return OnboardingLaunch.onboarding;

  final comparison = compareVersions(current, last);
  if (comparison == 0) return OnboardingLaunch.none;
  return comparison > 0
      ? OnboardingLaunch.upgradeDialog
      : OnboardingLaunch.none;
}
