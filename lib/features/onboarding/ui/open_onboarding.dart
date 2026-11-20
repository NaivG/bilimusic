import 'package:flutter/material.dart';

import 'package:bilimusic/features/onboarding/ui/onboarding_content.dart';
import 'package:bilimusic/features/onboarding/ui/onboarding_page.dart';
import 'package:bilimusic/shared/motion/motion.dart';

/// 从「设置 → 关于应用 → 查看引导」重新打开引导页。
///
/// 走独立路由而不是 [OnboardingGate]：引导页已经看过后门控不会再触发，
/// 这里只是让用户随时回看；关闭时直接 pop，不动 `last_boot_version`。
Future<void> openOnboarding(BuildContext context) {
  final navigator = Navigator.of(context);
  return navigator.push<void>(
    PageRouteBuilder<void>(
      transitionDuration: BmMotion.large,
      reverseTransitionDuration: BmMotion.medium,
      pageBuilder: (routeContext, animation, secondaryAnimation) {
        void close() => Navigator.of(routeContext).maybePop();
        return OnboardingPage(
          pages: onboardingPages,
          onDone: close,
          onSkip: close,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // 用 drive + CurveTween 而不是 CurvedAnimation：后者会向父动画挂
        // status listener，必须持有并 dispose；转场 builder 每帧都会重建，
        // 不适合在那里 new。
        final fade = animation.drive(CurveTween(curve: BmMotion.emphasized));
        return FadeTransition(opacity: fade, child: child);
      },
    ),
  );
}
