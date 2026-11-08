import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/controls/bm_field.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmField：40 高 / surfaceSunken 底 / focus 与错误边框 / label 与错误提示 /
/// 回调 / leading、trailing 尺寸。
void main() {
  testWidgets('高 40、surfaceSunken 填充、r10 无外边框、body/hint 排版', (tester) async {
    final colors = await _pumpField(tester, const BmField(hintText: '搜索'));

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(tester.getSize(find.byType(TextField)).height, 40);
    expect(textField.style?.fontSize, 15);
    expect(textField.style?.color, colors.textPrimary);

    final decoration = textField.decoration!;
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, colors.surfaceSunken);
    expect(decoration.isDense, isTrue);
    final idleBorder = decoration.enabledBorder! as OutlineInputBorder;
    expect(idleBorder.borderRadius, BmTokens.r10All);
    expect(idleBorder.borderSide, BorderSide.none);

    final hint = tester.widget<Text>(find.text('搜索'));
    expect(hint.style?.fontSize, 15);
    expect(hint.style?.color, colors.textTertiary);
  });

  testWidgets('聚焦后 focusedBorder 为 2px accentBorder', (tester) async {
    final colors = await _pumpField(tester, const BmField(hintText: '搜索'));

    final focusedBorder =
        tester
                .widget<TextField>(find.byType(TextField))
                .decoration!
                .focusedBorder!
            as OutlineInputBorder;
    expect(focusedBorder.borderSide.color, colors.accentBorder);
    expect(focusedBorder.borderSide.width, 2);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final decorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator),
    );
    expect(decorator.isFocused, isTrue);
    expect(decorator.decoration.focusedBorder, focusedBorder);
  });

  testWidgets('errorText → danger 边框 + caption 提示', (tester) async {
    final colors = await _pumpField(
      tester,
      const BmField(hintText: '搜索', errorText: '关键词不能为空'),
    );

    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    final errorBorder = decoration.enabledBorder! as OutlineInputBorder;
    expect(errorBorder.borderSide.color, colors.danger);
    expect(errorBorder.borderSide.width, 1);
    final focusedErrorBorder = decoration.focusedBorder! as OutlineInputBorder;
    expect(focusedErrorBorder.borderSide.color, colors.danger);
    expect(focusedErrorBorder.borderSide.width, 2);
    expect(
      (decoration.errorBorder! as OutlineInputBorder).borderSide.color,
      colors.danger,
    );
    expect(
      (decoration.focusedErrorBorder! as OutlineInputBorder).borderSide.color,
      colors.danger,
    );

    final error = tester.widget<Text>(find.text('关键词不能为空'));
    expect(error.style?.fontSize, 12);
    expect(error.style?.height, closeTo(16 / 12, 1e-9));
    expect(error.style?.color, colors.danger);
    expect(
      tester.getSize(find.byType(TextField)).height,
      40,
      reason: '错误提示在输入框下方，不撑高输入框',
    );
  });

  testWidgets('label 在输入框上方，13/18', (tester) async {
    await _pumpField(tester, const BmField(label: '关键词', hintText: '搜索'));

    final label = tester.widget<Text>(find.text('关键词'));
    expect(label.style?.fontSize, 13);
    expect(label.style?.height, closeTo(18 / 13, 1e-9));
    expect(
      tester.getBottomLeft(find.text('关键词')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
  });

  testWidgets('onChanged / onSubmitted 回调', (tester) async {
    String? changed;
    String? submitted;
    await _pumpField(
      tester,
      BmField(
        hintText: '搜索',
        onChanged: (value) => changed = value,
        onSubmitted: (value) => submitted = value,
      ),
    );

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pump();
    expect(changed, '周杰伦');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, '周杰伦');
  });

  testWidgets('width 固定 / 父级自适应，leading / trailing 图标 20', (tester) async {
    final colors = await _pumpField(
      tester,
      const BmField(
        width: 260,
        hintText: '搜索',
        leading: Icon(Icons.search),
        trailing: Icon(Icons.close),
      ),
    );
    expect(tester.getSize(find.byType(BmField)).width, 260);
    expect(tester.widget<Icon>(find.byIcon(Icons.search)).size, isNull);
    expect(_nearestIconTheme(tester, Icons.search).size, BmTokens.icon);
    expect(_nearestIconTheme(tester, Icons.search).color, colors.textSecondary);
    expect(_nearestIconTheme(tester, Icons.close).size, BmTokens.icon);

    await _pumpField(tester, const BmField(hintText: '搜索'), parentWidth: 320);
    expect(tester.getSize(find.byType(BmField)).width, 320);
  });
}

/// 从 Icon 向上找最近一层 [IconTheme]（BmField 用它兜底图标尺寸）。
IconThemeData _nearestIconTheme(WidgetTester tester, IconData icon) {
  var data = const IconThemeData();
  tester.element(find.byIcon(icon)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is IconTheme) {
      data = widget.data;
      return false;
    }
    return true;
  });
  return data;
}

/// 起一个只挂 [BmField] 的最小页面，返回当前主题的颜色角色。
Future<BmColors> _pumpField(
  WidgetTester tester,
  BmField field, {
  double? parentWidth,
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  Widget child = field;
  if (parentWidth != null) {
    child = SizedBox(width: parentWidth, child: field);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
  return theme.extension<BmColors>()!;
}
