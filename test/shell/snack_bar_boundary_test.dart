import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底部播放条的「边界 + toast 样式」回归测试。
void main() {
  // 真实主题：SnackBar 的 behavior / shape / insetPadding 都来自它
  final theme = ThemeRegistry.defaultTheme.dark();

  // 与实现保持一致的尺寸：横屏控制栏 88 / 90 / 96，迷你播放器胶囊 68、
  // 手机端离底 16、底部导航栏 56。
  const double landscapeControlHeight = 96;
  const double miniPlayerHeight = 68;
  const double miniPlayerGap = 16;
  const double bottomNavHeight = 56;

  // 与 AppComponentThemes.snackBar 的 insetPadding 对应
  const double horizontalInset = 16;
  const double verticalInset = 12;

  /// 按外壳的结构搭一个 Scaffold（body + 底槽），返回它的 ScaffoldMessenger。
  Future<ScaffoldMessengerState> pumpShell(
    WidgetTester tester,
    Widget bottomSlot,
  ) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: bottomSlot,
        ),
      ),
    );
    return messenger;
  }

  /// toast 真正可见的那块（外层 Material）。
  /// 不能用 SnackBar 自身的矩形：浮动样式把 insetPadding 也算在里面，
  /// 量出来是通栏的，看不出留白。
  Rect visibleToastRect(WidgetTester tester) {
    return tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
  }

  Future<void> showToast(
    WidgetTester tester,
    ScaffoldMessengerState messenger,
  ) async {
    messenger.showSnackBar(const SnackBar(content: Text('已添加到收藏')));
    await tester.pumpAndSettle();
  }

  testWidgets('横屏：toast 浮在底部控制栏上方', (tester) async {
    final chromeKey = GlobalKey();
    final messenger = await pumpShell(
      tester,
      SizedBox(key: chromeKey, height: landscapeControlHeight),
    );

    await showToast(tester, messenger);

    final toastRect = visibleToastRect(tester);
    final chromeRect = tester.getRect(find.byKey(chromeKey));
    expect(toastRect.overlaps(chromeRect), isFalse);
    // 底槽上沿 = contentBottom，toast 与它之间正好是 insetPadding 的下边距
    expect(chromeRect.top - toastRect.bottom, verticalInset);
    expect(toastRect.left, horizontalInset);
  });

  testWidgets('竖屏：toast 浮在迷你播放器上方', (tester) async {
    final miniPlayerKey = GlobalKey();
    final messenger = await pumpShell(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: miniPlayerGap),
            child: SizedBox(key: miniPlayerKey, height: miniPlayerHeight),
          ),
          const SizedBox(height: bottomNavHeight),
        ],
      ),
    );

    await showToast(tester, messenger);

    final toastRect = visibleToastRect(tester);
    final miniPlayerRect = tester.getRect(find.byKey(miniPlayerKey));
    expect(toastRect.overlaps(miniPlayerRect), isFalse);
    expect(miniPlayerRect.top - toastRect.bottom, verticalInset);
  });

  testWidgets('toast 是主题里的圆角浮动样式', (tester) async {
    final messenger = await pumpShell(
      tester,
      const SizedBox(height: landscapeControlHeight),
    );

    await showToast(tester, messenger);

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppTokens.radiusLg));
    expect(material.color, theme.colorScheme.surfaceContainerHigh);
  });
}
