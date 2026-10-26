import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/taste_graph_layout.dart';
import 'package:bilimusic/features/taste/ui/widgets/taste_graph_card.dart';

void main() {
  testWidgets('无共现边时显示空态', (tester) async {
    await tester.pumpWidget(_host(_profile(edges: const [])));

    expect(find.text('口味关系图'), findsOneWidget);
    expect(find.text('关系还不够清晰'), findsOneWidget);
  });

  testWidgets('有共现边时渲染关系图并支持清除选择', (tester) async {
    await tester.pumpWidget(_host(_profile()));
    await tester.pumpAndSettle();

    expect(find.text('口味关系图'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('关系还不够清晰'), findsNothing);
  });

  testWidgets('点击节点进入聚焦并展示详情', (tester) async {
    final profile = _profile();
    await tester.pumpWidget(_host(profile));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const Key('taste_graph_canvas'));
    final size = tester.getSize(canvas);
    final layout = TasteGraphLayout.compute(
      profile,
      width: size.width,
      height: size.height,
      maxNodes: size.width < 420 ? 24 : 32,
      maxEdgesPerNode: 3,
      iterations: 220,
    );
    final node = layout.nodeOf('jazz')!;
    await tester.tapAt(tester.getTopLeft(canvas) + Offset(node.x, node.y));
    await tester.pumpAndSettle();

    expect(find.text('口味权重 1.00 · 出现在 4 首歌'), findsOneWidget);
    expect(find.text('常一起出现'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('口味权重 1.00 · 出现在 4 首歌'), findsNothing);
  });
}

Widget _host(TasteProfile profile) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    useMaterial3: true,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        child: SingleChildScrollView(child: TasteGraphCard(profile: profile)),
      ),
    ),
  ),
);

TasteProfile _profile({List<TasteEdge>? edges}) => TasteProfile(
  keywords: const [
    TasteKeyword(term: 'jazz', weight: 1.0, df: 4),
    TasteKeyword(term: 'piano', weight: 0.8, df: 3),
    TasteKeyword(term: 'blues', weight: 0.6, df: 2),
  ],
  edges:
      edges ??
      const [
        TasteEdge(a: 'jazz', b: 'piano', weight: 0.5, support: 2),
        TasteEdge(a: 'blues', b: 'jazz', weight: 0.4, support: 2),
      ],
  sampleCount: 4,
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);
