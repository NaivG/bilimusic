import 'package:bilimusic/app/shells/widgets/desktop_window_controls.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmWindowControls：四个窗口控制按钮与中文 tooltip。
///
/// 只验证渲染与文案，不点按钮——最小化 / 关闭会走 `window_manager` 平台通道。
void main() {
  testWidgets('渲染画中画 / 最小化 / 最大化 / 关闭四个图标按钮', (tester) async {
    await _pumpControls(tester);

    expect(find.byType(BmIconButton), findsNWidgets(4));
    expect(find.byIcon(Icons.picture_in_picture_alt), findsOneWidget);
    expect(find.byIcon(Icons.minimize_rounded), findsOneWidget);
    expect(find.byIcon(Icons.crop_square_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('四个按钮都带中文 tooltip', (tester) async {
    await _pumpControls(tester);

    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message)
        .whereType<String>()
        .toList();
    expect(messages, <String>['画中画', '最小化', '最大化/还原', '关闭']);
  });
}

Future<void> _pumpControls(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeRegistry.defaultTheme.light(),
      home: const Scaffold(body: Center(child: BmWindowControls())),
    ),
  );
  await tester.pump();
}
