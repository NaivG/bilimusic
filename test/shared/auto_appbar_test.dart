import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内页 AppBar 的返回按钮策略：
/// - 竖屏、页面栈可返回时显示；
/// - 横屏外壳标题栏已提供返回入口，内页一律隐藏。
void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required Size size,
    Widget? leading,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AutoAppBar.generateAppBar(
                context: context,
                title: '测试页',
                leading: leading,
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    ShellPageManager.instance.push(ShellPage.changelog);
  });

  tearDown(() {
    final manager = ShellPageManager.instance;
    while (manager.canPop) {
      manager.pop();
    }
  });

  testWidgets('竖屏显示返回按钮', (tester) async {
    await pumpPage(tester, size: const Size(500, 800));

    expect(find.byIcon(Icons.arrow_back_ios_rounded), findsOneWidget);
    expect(find.text('测试页'), findsOneWidget);
  });

  testWidgets('横屏不显示返回按钮', (tester) async {
    await pumpPage(tester, size: const Size(1200, 800));

    expect(find.byIcon(Icons.arrow_back_ios_rounded), findsNothing);
    expect(find.text('测试页'), findsOneWidget);
  });

  testWidgets('横屏不显示自定义返回/关闭按钮', (tester) async {
    await pumpPage(
      tester,
      size: const Size(1200, 800),
      leading: IconButton(icon: const Icon(Icons.close), onPressed: () {}),
    );

    expect(find.byIcon(Icons.close), findsNothing);
  });
}
