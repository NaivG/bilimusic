import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/shared/widgets/app_menu_button.dart';
import 'package:super_context_menu/super_context_menu.dart';

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

    // 桌面菜单由 super_context_menu 的默认构建器绘制，文本组件来自
    // pixel_snap，不能按 widget 类型查找；从菜单项元素树定位点击区域。
    final menuItem = tester.element(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_MenuItemWidget',
      ),
    );
    final textElement = collectAllElementsFrom(
      menuItem,
      skipOffstage: false,
    ).firstWhere((e) => e.widget.runtimeType.toString() == 'Text');
    final textBox = textElement.renderObject! as RenderBox;
    final textRect = textBox.localToGlobal(Offset.zero) & textBox.size;

    await tester.tapAt(textRect.center);
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
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('测试项'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
