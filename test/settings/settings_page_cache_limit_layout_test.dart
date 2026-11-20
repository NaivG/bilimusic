import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/features/settings/ui/settings_page.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 设置页「数据」组里两个缓存上限行的排版冒烟测试。
///
/// 只验证三形态下两行都能建出、文案正确、没有 RenderFlex 溢出；真实外观
/// 仍以跑起来的 App 为准。数值行为在 `cache_limit_settings_test.dart`，
/// 淘汰逻辑在 `test/storage/`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettingsPage(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // 竖屏下表单更长，打开这个选项让页面接近真实默认形态。
      SettingsManager.KEY_ALWAYS_SHOW_MINI_PLAYER: true,
    });
    await SettingsManager().init();

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeRegistry.defaultTheme.light(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  const cases = <(String, Size)>[
    ('竖屏', Size(800, 1200)),
    ('横屏', Size(1280, 720)),
    ('方形', Size(1000, 1000)),
  ];

  for (final (label, size) in cases) {
    testWidgets(
      '$label ${size.width.toInt()}x${size.height.toInt()}：缓存上限两行可渲染',
      (tester) async {
        await pumpSettingsPage(tester, size);

        expect(find.text('音乐缓存上限'), findsOneWidget);
        expect(find.text('图片缓存上限'), findsOneWidget);
        // 默认档位：音乐 512 MB、图片 256 MB（1024 的倍数才显示 GB）。
        expect(find.text('512 MB'), findsOneWidget);
        expect(find.text('256 MB'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
