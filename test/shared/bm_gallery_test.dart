import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/gallery/bm_gallery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmGallery 预览页：12 套主题组合都能跑通。
void main() {
  testWidgets('6 主题 × 明暗切换、滚到底部均无异常', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: BmGalleryPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bm-gallery')), findsOneWidget);

    for (final descriptor in ThemeRegistry.all) {
      for (final brightness in Brightness.values) {
        await tester.tap(_comboHalf(descriptor.label, brightness));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${descriptor.id} · ${brightness.name} 切换时抛异常',
        );
      }
    }

    // 分区标题与 8 档排版规格都在页面上。
    expect(find.text('主题 × 亮度'), findsOneWidget);
    expect(find.text('颜色角色'), findsOneWidget);
    expect(find.text('排版 8 档'), findsOneWidget);
    expect(find.text('M0 动效'), findsOneWidget);
    const typeSpecs = <String>[
      '28/34 · w700',
      '22/28 · w700',
      '17/24 · w600',
      '15/22 · w400',
      '15/22 · w600',
      '13/18 · w500',
      '12/16 · w400',
      '11/14 · w500',
    ];
    for (final spec in typeSpecs) {
      expect(find.text(spec), findsOneWidget, reason: '排版规格 $spec 未渲染');
    }
    // 颜色角色分区逐个列出 BmColors 的角色名。
    for (final role in <String>[
      'hairline',
      'stateHover',
      'accentBorder',
      'chromeOpaque',
      'scrim',
      'dim',
    ]) {
      expect(find.text(role), findsOneWidget, reason: '颜色角色 $role 未渲染');
    }

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('M0 动效'), findsOneWidget);
    // P2 Chrome 与 M1 页面切换是新增的两个验收分区。
    expect(find.text('P2 Chrome'), findsOneWidget);
    expect(find.text('M1 页面切换'), findsOneWidget);
  });
}

/// 主题卡片里的「浅色 / 深色」色板（每张卡两块，按树序浅色在前）。
Finder _comboHalf(String label, Brightness brightness) {
  final card = find
      .ancestor(of: find.text(label), matching: find.byType(Container))
      .first;
  final halves = find.descendant(of: card, matching: find.byType(InkWell));
  return halves.at(brightness == Brightness.light ? 0 : 1);
}
