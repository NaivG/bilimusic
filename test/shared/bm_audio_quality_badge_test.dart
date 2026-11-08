import 'package:bilimusic/shared/ui/stage/bm_audio_quality_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BmAudioQualityBadge：档位 → 图标 / 文案，换档动画与 reduce motion。
void main() {
  const badgeFadeKey = ValueKey<String>('bm-audio-quality-badge-fade');
  const losslessIconKey = ValueKey<String>('bm-audio-quality-lossless-icon');
  const dolbyIconKey = ValueKey<String>('bm-audio-quality-dolby-icon');
  const dolbyGlowKey = ValueKey<String>('bm-audio-quality-dolby-glow');

  Future<void> pumpBadge(
    WidgetTester tester,
    String qualityId, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: BmAudioQualityBadge(qualityId: qualityId)),
          ),
        ),
      ),
    );
  }

  testWidgets('Hi-Res 无损显示 ALAC 标志 + 文案', (tester) async {
    await pumpBadge(tester, '30251');
    await tester.pumpAndSettle();

    expect(find.text('Hi-Res 无损'), findsOneWidget);
    expect(find.byKey(losslessIconKey), findsOneWidget);
    expect(find.byKey(dolbyIconKey), findsNothing);
  });

  testWidgets('杜比全景声只画字标（带一次性辉光）', (tester) async {
    await pumpBadge(tester, '30250');
    await tester.pump();

    expect(find.byKey(dolbyIconKey), findsOneWidget);
    expect(find.byKey(dolbyGlowKey), findsOneWidget);
    expect(find.text('杜比全景声'), findsNothing);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('标准档只显示文案', (tester) async {
    await pumpBadge(tester, '30280');
    await tester.pumpAndSettle();

    expect(find.text('192K HQ'), findsOneWidget);
    expect(find.byKey(losslessIconKey), findsNothing);
    expect(find.byKey(dolbyIconKey), findsNothing);
  });

  testWidgets('未知代码回退到 192K HQ', (tester) async {
    await pumpBadge(tester, '99999');
    await tester.pumpAndSettle();

    expect(find.text('192K HQ'), findsOneWidget);
  });

  testWidgets('换档后文案与标志跟着换', (tester) async {
    await pumpBadge(tester, '30280');
    await tester.pumpAndSettle();
    expect(find.text('192K HQ'), findsOneWidget);

    await pumpBadge(tester, '30251');
    await tester.pumpAndSettle();

    expect(find.text('Hi-Res 无损'), findsOneWidget);
    expect(find.byKey(losslessIconKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion 下直接落到终态，且不画辉光', (tester) async {
    await pumpBadge(tester, '30250', reduceMotion: true);
    await tester.pump();

    final fade = tester.widget<FadeTransition>(find.byKey(badgeFadeKey));
    expect(fade.opacity.value, 1);
    expect(find.byKey(dolbyGlowKey), findsNothing);
  });

  testWidgets('语义标签带音质文案', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpBadge(tester, '30250');
    await tester.pump();

    expect(find.bySemanticsLabel('音质：杜比全景声'), findsOneWidget);
    handle.dispose();
  });
}
