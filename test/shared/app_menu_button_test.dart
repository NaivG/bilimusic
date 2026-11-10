import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/overlay/bm_sheet.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/widgets/app_menu_button.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 一个带子菜单的菜单树：悬停 / 方向键都能展开第二层。
Menu _nestedMenu() {
  return Menu(
    children: [
      Menu(
        title: '添加到歌单',
        children: [MenuAction(title: '歌单一', callback: () {})],
      ),
      MenuAction(title: '移除', callback: () {}),
    ],
  );
}

void main() {
  testWidgets('desktop menu opens as a context-menu overlay', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMenuButton(
              menuBuilder: (_) => Menu(
                children: [
                  MenuAction(title: '测试项', callback: () => tapped = true),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppMenuButton));
    await tester.pumpAndSettle();

    // 桌面菜单是 Lucent 的 AppDesktopMenuWidgetBuilder 画的，行文案就是普通 Text。
    expect(find.text('测试项'), findsOneWidget);
    expect(find.byType(BmMenuRow), findsOneWidget);

    await tester.tap(find.text('测试项'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile menu opens as a bottom sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMenuButton(
              menuBuilder: (_) => Menu(
                children: [
                  MenuAction(title: '测试项', callback: () => tapped = true),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('测试项'), findsOneWidget);
    // 移动端菜单浮层由 showBmSheet 承载，面板类型是 Lucent 的 BmSheet。
    expect(find.byType(BmSheet), findsOneWidget);
    expect(find.byType(BmMenuRow), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('测试项'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop submenu opens on hover', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: AppMenuButton(menuBuilder: (_) => _nestedMenu())),
        ),
      ),
    );

    await tester.tap(find.byType(AppMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('添加到歌单'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('添加到歌单')));
    // 悬停 100ms 后才推入子菜单。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('歌单一'), findsOneWidget);
    expect(find.byType(BmMenuSurface), findsNWidgets(2));

    await tester.tapAt(const Offset(BmTokens.s1, BmTokens.s1));
    await tester.pumpAndSettle();
    expect(find.byType(BmMenuSurface), findsNothing);
    // 安全三角命中区会挂一个 500ms 的清理计时器，等它落地再结束用例。
    await tester.pump(const Duration(milliseconds: 700));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop menu keyboard: 方向键展开子菜单', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: AppMenuButton(menuBuilder: (_) => _nestedMenu())),
        ),
      ),
    );

    await tester.tap(find.byType(AppMenuButton));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('歌单一'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
