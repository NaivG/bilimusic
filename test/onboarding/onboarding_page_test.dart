import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/features/onboarding/ui/onboarding_content.dart';
import 'package:bilimusic/features/onboarding/ui/onboarding_page.dart';
import 'package:bilimusic/features/onboarding/ui/open_onboarding.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 引导页的翻页、回看与布局。
///
/// 只测结构（翻页、回调、主题试穿、各视口不溢出），不测像素：插画是
/// token 拼出来的，尺寸随视口变化，像素断言会变成噪音。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> resetSettings([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    await SettingsManager().init();
  }

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeRegistry.defaultTheme.light(),
        home: child,
      ),
    );
  }

  group('OnboardingPage', () {
    testWidgets('从头翻到尾，结束按钮回调一次', (tester) async {
      await resetSettings();
      var done = 0;
      await tester.pumpWidget(
        wrap(OnboardingPage(pages: onboardingPages, onDone: () => done++)),
      );
      await tester.pumpAndSettle();

      expect(find.text('把 B 站当音乐库'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);

      for (var page = 1; page < onboardingPages.length; page++) {
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
      }

      expect(find.text('去听点什么'), findsOneWidget);
      expect(find.text('开始聆听'), findsOneWidget);
      expect(done, 0);

      await tester.tap(find.text('开始聆听'));
      await tester.pumpAndSettle();
      expect(done, 1);
    });

    testWidgets('跳过回调独立于结束回调', (tester) async {
      await resetSettings();
      var done = 0;
      var skipped = 0;
      await tester.pumpWidget(
        wrap(
          OnboardingPage(
            pages: onboardingPages,
            onDone: () => done++,
            onSkip: () => skipped++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();

      expect(skipped, 1);
      expect(done, 0);
    });

    testWidgets('外观页主题色板可点击换肤', (tester) async {
      await resetSettings();
      await tester.pumpWidget(
        wrap(OnboardingPage(pages: onboardingPages, onDone: () {})),
      );
      await tester.pumpAndSettle();

      // 欢迎 → 登录 → 找歌 → 播放 → 离线 → 外观，共 5 次。
      for (var index = 0; index < 5; index++) {
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
      }

      expect(find.text('六套主题，随心切换'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('whats-new-theme-nocturne')),
      );
      await tester.pumpAndSettle();

      expect(SettingsManager().theme, 'nocturne');
    });

    testWidgets('手机竖屏 412×892 逐页渲染不溢出', (tester) async {
      await resetSettings();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 892);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(OnboardingPage(pages: onboardingPages, onDone: () {})),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (var page = 2; page <= onboardingPages.length; page++) {
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '第 $page 页在竖屏 412×892 下布局溢出',
        );
      }

      expect(find.text('开始聆听'), findsOneWidget);
    });

    testWidgets('手机横屏 780×360 逐页渲染不溢出', (tester) async {
      await resetSettings();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(780, 360);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(OnboardingPage(pages: onboardingPages, onDone: () {})),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (var page = 2; page <= onboardingPages.length; page++) {
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '第 $page 页在横屏 780×360 下布局溢出',
        );
      }
    });
  });

  group('回看入口', () {
    testWidgets('openOnboarding 从设置入口推入引导页', (tester) async {
      await resetSettings();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: ThemeRegistry.defaultTheme.light(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openOnboarding(context),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('把 B 站当音乐库'), findsOneWidget);

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
    });
  });
}
