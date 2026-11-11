import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/overlay/bm_overlays.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底部播放条的「边界 + toast 样式」回归测试。
void main() {
  // 真实主题：SnackBar 的 behavior / shape / insetPadding 都来自它
  final theme = ThemeRegistry.defaultTheme.dark();
  final colors = theme.extension<BmColors>()!;

  // 与实现保持一致的尺寸：横屏控制栏固定 90，迷你播放器胶囊 68、
  // 手机端离底 16、底部导航栏 56。
  const double landscapeControlHeight = BmTokens.playbarHeight;
  const double miniPlayerHeight = 68;
  const double miniPlayerGap = 16;
  const double bottomNavHeight = 56;

  // 与 AppComponentThemes.snackBar 的 insetPadding 对应
  const double horizontalInset = 16;
  const double verticalInset = 12;

  /// 按外壳的结构搭一个 Scaffold（body + 底槽），返回可弹 toast 的上下文。
  Future<BuildContext> pumpShell(WidgetTester tester, Widget bottomSlot) async {
    late BuildContext shellContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              shellContext = context;
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: bottomSlot,
        ),
      ),
    );
    return shellContext;
  }

  /// toast 真正可见的那块：BmToast 自绘的 surface（Material）。
  /// 不能用 SnackBar 自身的矩形：浮动样式把 insetPadding 也算在里面，
  /// 量出来是通栏的，看不出留白；SnackBar 外壳现在还是透明无描边的。
  Rect visibleToastRect(WidgetTester tester) {
    return tester.getRect(
      find
          .descendant(of: find.byType(BmToast), matching: find.byType(Material))
          .first,
    );
  }

  Future<void> showToast(WidgetTester tester, BuildContext context) async {
    showBmToast(context, '已添加到收藏');
    await tester.pumpAndSettle();
  }

  testWidgets('横屏：toast 浮在底部控制栏上方', (tester) async {
    final chromeKey = GlobalKey();
    final context = await pumpShell(
      tester,
      SizedBox(key: chromeKey, height: landscapeControlHeight),
    );

    await showToast(tester, context);

    final toastRect = visibleToastRect(tester);
    final chromeRect = tester.getRect(find.byKey(chromeKey));
    expect(toastRect.overlaps(chromeRect), isFalse);
    // 底槽上沿 = contentBottom，toast 与它之间正好是 insetPadding 的下边距
    expect(chromeRect.top - toastRect.bottom, verticalInset);
    expect(toastRect.left, horizontalInset);
  });

  testWidgets('竖屏：toast 浮在迷你播放器上方', (tester) async {
    final miniPlayerKey = GlobalKey();
    final context = await pumpShell(
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

    await showToast(tester, context);

    final toastRect = visibleToastRect(tester);
    final miniPlayerRect = tester.getRect(find.byKey(miniPlayerKey));
    expect(toastRect.overlaps(miniPlayerRect), isFalse);
    expect(miniPlayerRect.top - toastRect.bottom, verticalInset);
  });

  testWidgets('toast 是 BmToast 自绘的圆角浮动样式', (tester) async {
    final context = await pumpShell(
      tester,
      const SizedBox(height: landscapeControlHeight),
    );

    await showToast(tester, context);

    // SnackBar 外壳只保留定位几何：透明、无内边距、无描边。
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, Colors.transparent);
    expect(snackBar.padding, EdgeInsets.zero);
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect((snackBar.shape! as RoundedRectangleBorder).side, BorderSide.none);

    // 可见面是 BmToast 自己的 Material：floating 底 + 14 圆角 + 0.5 hairline。
    final material = tester.widget<Material>(
      find
          .descendant(of: find.byType(BmToast), matching: find.byType(Material))
          .first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BmTokens.r14All);
    expect(material.color, colors.floating);
    expect(shape.side.color, colors.hairline);
    expect(shape.side.width, 0.5);
  });
}
