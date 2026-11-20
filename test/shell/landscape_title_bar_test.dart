import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/shells/landscape/landscape_title_bar.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 横屏标题栏：状态栏 / 刘海高度算进 chrome，内容整体下移但不压系统栏。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 1024 宽按断点取 52 高的标题栏。
  const double designHeight = 52;

  Future<void> pumpBar(
    WidgetTester tester, {
    required double topPadding,
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 600);
    addTearDown(tester.view.reset);

    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeRegistry.defaultTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(1024, 600),
              padding: EdgeInsets.only(top: topPadding),
            ),
            child: Scaffold(
              body: LandscapeTitleBar(
                pageTitle: '首页',
                searchController: controller,
                searchFocusNode: focusNode,
                onSearchChanged: (_) {},
                onSearchSubmit: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('状态栏高度算进标题栏总高，搜索框躲在系统栏下面', (tester) async {
    await pumpBar(tester, topPadding: 48);

    expect(
      tester.getSize(find.byType(LandscapeTitleBar)).height,
      designHeight + 48,
      reason: '内容高度保持设计稿 52，顶部额外让出状态栏 48',
    );
    expect(
      tester.getRect(find.byType(TextField)).top,
      greaterThanOrEqualTo(48),
      reason: '搜索框不能画到状态栏底下',
    );
  });
}
