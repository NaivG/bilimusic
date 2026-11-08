import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/widgets/lyric_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lyrics/widgets/lyric_section.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/motion/spring_curve.dart';

/// 歌词版式 / 动效回归：竖屏 AM 大字左对齐、逐字填充；横屏同一套弹簧动画。
void main() {
  Future<LyricStyle> pumpStyle(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final controller = LyricController()
      ..loadLyricModel(
        LyricModel(
          lines: [
            LyricLine(
              start: Duration.zero,
              end: const Duration(seconds: 4),
              text: 'Dance, dance with me, dance',
              translation: '你是我能感受到的光',
            ),
            LyricLine(
              start: const Duration(seconds: 4),
              end: const Duration(seconds: 8),
              text: "You're the light I feel",
            ),
          ],
        ),
      );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricSection(
            lyricController: controller,
            position: Duration.zero,
          ),
        ),
      ),
    );

    return tester.widget<LyricView>(find.byType(LyricView)).style!;
  }

  testWidgets('竖屏：大字号左对齐 + 当前行放大 + 逐字填充 + 弹簧滚动', (tester) async {
    final style = await pumpStyle(tester, const Size(393, 852));

    expect(style.lineTextAlign, TextAlign.left);
    expect(style.contentAlignment, CrossAxisAlignment.start);
    expect(style.textStyle.fontSize, greaterThanOrEqualTo(32));
    // 当前行按 100:97 行缩放略放大。
    expect(style.activeStyle.fontSize, greaterThan(style.textStyle.fontSize!));
    expect(style.activeHighlightColor, isNotNull);
    expect(style.activeHighlightExtraFadeWidth, greaterThan(0));

    expect(style.scrollCurve, isA<SpringCurve>());
    expect(style.scrollAnimationBuilder, isNotNull);
    expect(style.switchEnterCurve, isA<SpringCurve>());
    expect(style.switchExitCurve, isA<SpringCurve>());
    expect(style.scrollDuration, BmMotion.lyricScrollMax);
    expect(style.switchEnterDuration, BmMotion.lyricSwitchMax);
    expect(style.switchExitDuration, BmMotion.lyricSwitchMax);
  });

  testWidgets('横屏：与竖屏同一套逐字填充 / 弹簧动画', (tester) async {
    final style = await pumpStyle(tester, const Size(1280, 800));

    expect(style.lineTextAlign, TextAlign.left);
    // 横屏桌面档放大后：其他行 34 / 当前行 40 / 行距 32。
    expect(style.textStyle.fontSize, 34);
    expect(style.activeStyle.fontSize, 40);
    expect(style.lineGap, 32);
    expect(style.translationLineGap, 10);
    expect(style.activeHighlightColor, isNotNull);
    expect(style.scrollCurve, isA<SpringCurve>());
    expect(style.scrollAnimationBuilder, isNotNull);
    expect(style.switchEnterCurve, isA<SpringCurve>());
    expect(style.switchExitCurve, isA<SpringCurve>());
  });

  testWidgets('方屏：保持紧凑居中，不套用 AM 大字与弹簧', (tester) async {
    final style = await pumpStyle(tester, const Size(320, 320));

    expect(style.lineTextAlign, TextAlign.center);
    expect(style.textStyle.fontSize, lessThan(20));
    expect(style.scrollCurve, isNot(isA<SpringCurve>()));
  });
}
