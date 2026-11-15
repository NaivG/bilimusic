import 'package:bilimusic/shared/ui/chrome/vertical_bar_toolbar.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPhone Duo 有竖栏时，二级页导航栏的返回键和图标按钮放进竖栏；
/// 只有文字的按钮留在导航栏里。
void main() {
  Future<VerticalBarToolbarController?> pumpPage(
    WidgetTester tester, {
    required bool withBar,
  }) async {
    final controller = withBar ? VerticalBarToolbarController() : null;
    addTearDown(() => controller?.dispose());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(466, 678)),
          child: Row(
            children: [
              Expanded(
                child: VerticalBarToolbarScope(
                  controller: controller,
                  child: Scaffold(
                    appBar: AutoAppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded),
                        onPressed: () {},
                      ),
                      title: const Text('离线缓存'),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () {},
                        ),
                        TextButton(onPressed: () {}, child: const Text('全部')),
                      ],
                    ),
                  ),
                ),
              ),
              if (controller != null)
                VerticalBarToolbar(controller: controller, width: 84),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  Finder inAppBar(Finder finder) =>
      find.descendant(of: find.byType(AppBar), matching: finder);

  testWidgets('有竖栏：返回键和图标按钮进竖栏，文字按钮留在导航栏', (tester) async {
    final controller = await pumpPage(tester, withBar: true);

    expect(controller!.items, hasLength(2));
    expect(inAppBar(find.byIcon(Icons.arrow_back_ios_rounded)), findsNothing);
    expect(inAppBar(find.byIcon(Icons.refresh)), findsNothing);
    expect(inAppBar(find.text('全部')), findsOneWidget);
    expect(inAppBar(find.text('离线缓存')), findsOneWidget);

    final bar = find.byType(VerticalBarToolbar);
    expect(
      find.descendant(
        of: bar,
        matching: find.byIcon(Icons.arrow_back_ios_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.refresh)),
      findsOneWidget,
    );
  });

  testWidgets('没有竖栏：按钮照常在导航栏里', (tester) async {
    await pumpPage(tester, withBar: false);

    expect(inAppBar(find.byIcon(Icons.arrow_back_ios_rounded)), findsOneWidget);
    expect(inAppBar(find.byIcon(Icons.refresh)), findsOneWidget);
    expect(inAppBar(find.text('全部')), findsOneWidget);
  });

  testWidgets('页面离开后撤销登记', (tester) async {
    final controller = await pumpPage(tester, withBar: true);
    expect(controller!.items, isNotEmpty);

    await tester.pumpWidget(
      VerticalBarToolbarScope(
        controller: controller,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    expect(controller.items, isEmpty);
  });
}
