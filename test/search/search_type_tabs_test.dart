import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/features/search/ui/search_type_tabs.dart';
import 'package:bilimusic/shared/ui/controls/bm_chip.dart';

void main() {
  testWidgets('分段 tab 用 Wrap 换行，窄屏不横向滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SearchResultType? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SearchTypeTabs(
              selectedType: SearchResultType.video,
              onTypeChanged: (type) => selected = type,
              availableTypes: SearchResultType.values
                  .where((type) => type != SearchResultType.upuser)
                  .toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BmChip), findsNWidgets(5));
    // Wrap 在 280 可用宽度内会分成多行。
    expect(tester.getSize(find.byType(SearchTypeTabs)).height, greaterThan(28));

    final horizontal = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .where(
          (scrollable) =>
              scrollable.axisDirection == AxisDirection.left ||
              scrollable.axisDirection == AxisDirection.right,
        );
    expect(horizontal, isEmpty);

    await tester.tap(find.text('专辑'));
    expect(selected, SearchResultType.album);
  });
}
