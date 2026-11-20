import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/onboarding/onboarding_gate.dart';
import 'package:bilimusic/features/onboarding/onboarding_provider.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 启动门控：首启 / 同版本 / 升级 / 更新日志跳转。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> resetSettings([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    await SettingsManager().init();
  }

  Widget wrap({required Widget child, required String? lastBootVersion}) {
    return ProviderScope(
      overrides: [
        lastBootVersionProvider.overrideWith((ref) async => lastBootVersion),
      ],
      child: MaterialApp(
        theme: ThemeRegistry.defaultTheme.light(),
        home: child,
      ),
    );
  }

  setUp(() {
    ShellPageManager.instance.goToTab(0);
  });

  tearDown(() {
    ShellPageManager.instance.goToTab(0);
  });

  testWidgets('首次启动盖住应用，跳过后写回版本且不再出现', (tester) async {
    await resetSettings();
    await tester.pumpWidget(
      wrap(
        lastBootVersion: null,
        child: const OnboardingGate(
          currentVersion: '1.12.0',
          child: Text('APP'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP'), findsOneWidget);
    expect(find.text('把 B 站当音乐库'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsManager.KEY_LAST_BOOT_VERSION), '1.12.0');

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(find.text('把 B 站当音乐库'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('版本没变时直接放行，不盖引导也不弹升级', (tester) async {
    await resetSettings(<String, Object>{
      SettingsManager.KEY_LAST_BOOT_VERSION: '1.12.0',
    });
    await tester.pumpWidget(
      wrap(
        lastBootVersion: '1.12.0',
        child: const OnboardingGate(
          currentVersion: '1.12.0',
          child: Text('APP'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP'), findsOneWidget);
    expect(find.text('把 B 站当音乐库'), findsNothing);
    expect(find.text('已升级至 1.12.0'), findsNothing);
  });

  testWidgets('版本变大时弹升级弹窗，稍后关闭并写回版本', (tester) async {
    await resetSettings(<String, Object>{
      SettingsManager.KEY_LAST_BOOT_VERSION: '1.11.0',
    });
    await tester.pumpWidget(
      wrap(
        lastBootVersion: '1.11.0',
        child: const OnboardingGate(
          currentVersion: '1.12.0',
          child: Text('APP'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP'), findsOneWidget);
    expect(find.text('已升级至 1.12.0'), findsOneWidget);
    expect(find.text('把 B 站当音乐库'), findsNothing);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.text('已升级至 1.12.0'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsManager.KEY_LAST_BOOT_VERSION), '1.12.0');
  });

  testWidgets('升级弹窗可以跳到更新日志', (tester) async {
    await resetSettings(<String, Object>{
      SettingsManager.KEY_LAST_BOOT_VERSION: '1.11.0',
    });
    await tester.pumpWidget(
      wrap(
        lastBootVersion: '1.11.0',
        child: const OnboardingGate(
          currentVersion: '1.12.0',
          child: Text('APP'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看更新日志'));
    await tester.pumpAndSettle();

    expect(find.text('已升级至 1.12.0'), findsNothing);
    expect(ShellPageManager.instance.currentPage, ShellPage.changelog);
  });
}
