import 'package:bilimusic/shared/ui/stage/bm_stage_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmStageBackdrop：纯黑底座、流体开关、关闭流体时的主色纯色底与切歌颜色过渡。
void main() {
  const blue = Color(0xFF3B6EA5);
  const red = Color(0xFFB53B4A);
  const solidKey = ValueKey<String>('bm-stage-solid');

  Future<void> pumpBackdrop(
    WidgetTester tester, {
    Color? color = blue,
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

  /// 纯色层当前渲染出来的颜色（动画中间态也能读到）。
  Color? solidColor(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(solidKey),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).color;
  }

  /// 纯色层这帧的目标颜色（AnimatedContainer 的 color 参数折进 decoration）。
  Color? targetSolidColor(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(find.byKey(solidKey));
    return (container.decoration as BoxDecoration?)?.color;
  }

  testWidgets('底座是不透明纯黑', (tester) async {
    await pumpBackdrop(tester);

    final base = tester.widget<ColoredBox>(
      find.byKey(const ValueKey<String>('bm-stage-base')),
    );
    expect(base.color, Colors.black);
    expect(base.color.a, 1.0);
  });

  testWidgets('关闭流体后铺封面主色纯色层，不再画封面虚化层', (tester) async {
    await pumpBackdrop(
      tester,
      fluid: false,
      coverUrl: 'https://example.com/a.jpg',
    );

    expect(find.byKey(solidKey), findsOneWidget);
    expect(solidColor(tester), isNot(Colors.black));
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

  testWidgets('主色压到 Stage 暗色区间，色相保持不变', (tester) async {
    await pumpBackdrop(tester, fluid: false);
    await tester.pumpAndSettle();

    final solid = HSLColor.fromColor(solidColor(tester)!);
    final source = HSLColor.fromColor(blue);
    expect(solid.hue, closeTo(source.hue, 0.5));
    expect(solid.lightness, closeTo(0.40, 0.001));
    expect(solid.lightness, lessThan(source.lightness));
  });

  testWidgets('没有主色时纯色层保持纯黑', (tester) async {
    await pumpBackdrop(tester, fluid: false, color: null);

    expect(find.byKey(solidKey), findsOneWidget);
    expect(solidColor(tester), Colors.black);
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

  testWidgets('关闭流体后切歌会做颜色过渡', (tester) async {
    await pumpBackdrop(tester, fluid: false);
    await tester.pumpAndSettle();
    final before = solidColor(tester);

    await pumpBackdrop(tester, fluid: false, color: red);
    final target = targetSolidColor(tester);

    await tester.pump(const Duration(milliseconds: 120));
    final mid = solidColor(tester);
    expect(mid, isNot(before));
    expect(mid, isNot(target));

    await tester.pumpAndSettle();
    expect(solidColor(tester), target);
  });

  testWidgets('reduce motion 下切歌直接落到目标色', (tester) async {
    await pumpBackdrop(tester, fluid: false, reduceMotion: true);
    await tester.pumpAndSettle();

    await pumpBackdrop(tester, fluid: false, color: red, reduceMotion: true);
    final target = targetSolidColor(tester);
    await tester.pump();

    expect(solidColor(tester), target);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('切歌时流体层色彩过渡会重绘', (tester) async {
    await pumpBackdrop(tester);
    final before = fluidLayer(tester).painter;

    await pumpBackdrop(tester, color: red);
    await tester.pump(const Duration(milliseconds: 120));

    expect(identical(before, fluidLayer(tester).painter), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion 下切歌流体层直接落到目标色', (tester) async {
    await pumpBackdrop(tester, reduceMotion: true);
    final before = fluidLayer(tester).painter;

    await pumpBackdrop(tester, color: red, reduceMotion: true);
    expect(tester.binding.transientCallbackCount, 0);
    expect(identical(before, fluidLayer(tester).painter), isFalse);
  });
}
