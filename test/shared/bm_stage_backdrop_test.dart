import 'package:bilimusic/shared/ui/stage/bm_stage_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmStageBackdrop：纯黑底座、流体开关与切歌色彩过渡。
void main() {
  const blue = Color(0xFF3B6EA5);
  const red = Color(0xFFB53B4A);

  Future<void> pumpBackdrop(
    WidgetTester tester, {
    Color color = blue,
    bool fluid = true,
    bool reduceMotion = false,
    String coverUrl = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: BmStageBackdrop(
              coverUrl: coverUrl,
              dominantColor: color,
              fluid: fluid,
            ),
          ),
        ),
      ),
    );
  }

  CustomPaint fluidLayer(WidgetTester tester) {
    return tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(BmStageBackdrop),
        matching: find.byType(CustomPaint),
      ),
    );
  }

  testWidgets('底座是不透明纯黑', (tester) async {
    await pumpBackdrop(tester);

    final base = tester.widget<ColoredBox>(
      find.byKey(const ValueKey<String>('bm-stage-base')),
    );
    expect(base.color, Colors.black);
    expect(base.color.a, 1.0);
  });

  testWidgets('关闭流体后只保留纯黑底座', (tester) async {
    await pumpBackdrop(
      tester,
      fluid: false,
      coverUrl: 'https://example.com/a.jpg',
    );

    expect(
      find.descendant(
        of: find.byType(BmStageBackdrop),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(BmStageBackdrop),
        matching: find.byType(ImageFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets('流体开启时包含色层', (tester) async {
    await pumpBackdrop(tester);

    expect(
      find.descendant(
        of: find.byType(BmStageBackdrop),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('静态层各自包 RepaintBoundary，位置 tick 不重绘背景', (tester) async {
    await pumpBackdrop(tester);
    expect(
      find.descendant(
        of: find.byType(BmStageBackdrop),
        matching: find.byType(RepaintBoundary),
      ),
      findsNWidgets(2),
    );

    await pumpBackdrop(tester, fluid: false);
    expect(
      find.descendant(
        of: find.byType(BmStageBackdrop),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });

  testWidgets('切歌时色彩过渡会重绘', (tester) async {
    await pumpBackdrop(tester);
    final before = fluidLayer(tester).painter;

    await pumpBackdrop(tester, color: red);
    await tester.pump(const Duration(milliseconds: 120));

    expect(identical(before, fluidLayer(tester).painter), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion 下切歌直接落到目标色', (tester) async {
    await pumpBackdrop(tester, reduceMotion: true);
    final before = fluidLayer(tester).painter;

    await pumpBackdrop(tester, color: red, reduceMotion: true);
    expect(tester.binding.transientCallbackCount, 0);
    expect(identical(before, fluidLayer(tester).painter), isFalse);
  });
}
