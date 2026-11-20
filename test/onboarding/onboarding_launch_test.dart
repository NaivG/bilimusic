import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/onboarding/onboarding_launch.dart';

void main() {
  group('decideOnboardingLaunch', () {
    test('没有历史版本 → 完整引导', () {
      expect(
        decideOnboardingLaunch(currentVersion: '1.12.0', lastBootVersion: null),
        OnboardingLaunch.onboarding,
      );
    });

    test('空串按没有历史版本处理', () {
      expect(
        decideOnboardingLaunch(currentVersion: '1.12.0', lastBootVersion: '  '),
        OnboardingLaunch.onboarding,
      );
    });

    test('版本相同 → 不打扰', () {
      expect(
        decideOnboardingLaunch(
          currentVersion: '1.12.0',
          lastBootVersion: '1.12.0',
        ),
        OnboardingLaunch.none,
      );
    });

    test('build 号不同不算升级', () {
      expect(
        decideOnboardingLaunch(
          currentVersion: '1.12.0+301',
          lastBootVersion: '1.12.0+300',
        ),
        OnboardingLaunch.none,
      );
    });

    test('版本变大 → 升级弹窗', () {
      expect(
        decideOnboardingLaunch(
          currentVersion: '1.13.0',
          lastBootVersion: '1.12.0',
        ),
        OnboardingLaunch.upgradeDialog,
      );
    });

    test('版本变小（降级）→ 不打扰', () {
      expect(
        decideOnboardingLaunch(
          currentVersion: '1.11.0',
          lastBootVersion: '1.12.0',
        ),
        OnboardingLaunch.none,
      );
    });

    test('按数字而不是字符串比较版本', () {
      expect(
        decideOnboardingLaunch(
          currentVersion: '1.10.0',
          lastBootVersion: '1.9.0',
        ),
        OnboardingLaunch.upgradeDialog,
      );
    });

    test('前后空白不影响判断', () {
      expect(
        decideOnboardingLaunch(
          currentVersion: ' 1.13.0 ',
          lastBootVersion: '1.12.0 ',
        ),
        OnboardingLaunch.upgradeDialog,
      );
    });
  });
}
