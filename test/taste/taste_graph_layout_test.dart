import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/taste_graph_layout.dart';

void main() {
  group('TasteGraphLayout', () {
    test('空画像 → 空布局', () {
      final layout = TasteGraphLayout.compute(
        TasteProfile(updatedAt: DateTime.now()),
        width: 400,
        height: 320,
      );
      expect(layout.isEmpty, true);
      expect(layout.edges, isEmpty);
    });

    test('节点坐标有限且落在画布内，度数等于边端点计数', () {
      final layout = TasteGraphLayout.compute(
        _profile(),
        width: 400,
        height: 320,
      );

      expect(layout.nodes.length, 3);
      expect(layout.edges.length, 2);
      for (final node in layout.nodes) {
        expect(node.x.isFinite, true);
        expect(node.y.isFinite, true);
        expect(node.x, inInclusiveRange(0, 400));
        expect(node.y, inInclusiveRange(0, 320));
        expect(node.radius, greaterThan(0));
      }
      final degreeSum = layout.nodes.fold<int>(
        0,
        (sum, node) => sum + node.degree,
      );
      expect(degreeSum, layout.edges.length * 2);
    });

    test('同输入同尺寸布局确定', () {
      final a = TasteGraphLayout.compute(_profile(), width: 400, height: 320);
      final b = TasteGraphLayout.compute(_profile(), width: 400, height: 320);

      expect(a.nodes.length, b.nodes.length);
      for (var i = 0; i < a.nodes.length; i++) {
        expect(a.nodes[i].term, b.nodes[i].term);
        expect(a.nodes[i].x, closeTo(b.nodes[i].x, 1e-9));
        expect(a.nodes[i].y, closeTo(b.nodes[i].y, 1e-9));
      }
    });

    test('maxNodes 截断后只保留两端都在图里的边', () {
      final layout = TasteGraphLayout.compute(
        _profile(),
        width: 400,
        height: 320,
        maxNodes: 2,
      );

      expect(layout.nodes.length, 2);
      final terms = {for (final node in layout.nodes) node.term};
      for (final edge in layout.edges) {
        expect(terms.contains(edge.a.term), true);
        expect(terms.contains(edge.b.term), true);
      }
    });

    test('没有边时仍返回可绘制的节点布局', () {
      final layout = TasteGraphLayout.compute(
        TasteProfile(
          keywords: const [
            TasteKeyword(term: 'jazz', weight: 1.0, df: 2),
            TasteKeyword(term: 'piano', weight: 0.8, df: 2),
            TasteKeyword(term: 'blues', weight: 0.6, df: 2),
          ],
          updatedAt: DateTime.now(),
        ),
        width: 400,
        height: 320,
      );

      expect(layout.nodes.length, 3);
      expect(layout.edges, isEmpty);
      for (final node in layout.nodes) {
        expect(node.x.isFinite, true);
        expect(node.y.isFinite, true);
      }
    });

    test('单节点居中', () {
      final layout = TasteGraphLayout.compute(
        TasteProfile(
          keywords: const [TasteKeyword(term: 'solo', weight: 1.0, df: 2)],
          updatedAt: DateTime.now(),
        ),
        width: 400,
        height: 320,
      );

      expect(layout.nodes.length, 1);
      expect(layout.nodes.single.x, closeTo(200, 0.001));
      expect(layout.nodes.single.y, closeTo(160, 0.001));
      expect(layout.edges, isEmpty);
    });

    test('edgesOf 返回与节点直接相连的边', () {
      final layout = TasteGraphLayout.compute(
        _profile(),
        width: 400,
        height: 320,
      );

      expect(layout.edgesOf('jazz').length, 2);
      expect(layout.edgesOf('piano').length, 1);
      expect(layout.edgesOf('nope'), isEmpty);
    });
  });
}

TasteProfile _profile() => TasteProfile(
  keywords: const [
    TasteKeyword(term: 'jazz', weight: 1.0, df: 4),
    TasteKeyword(term: 'piano', weight: 0.8, df: 3),
    TasteKeyword(term: 'blues', weight: 0.6, df: 2),
  ],
  edges: const [
    TasteEdge(a: 'jazz', b: 'piano', weight: 0.5, support: 2),
    TasteEdge(a: 'blues', b: 'jazz', weight: 0.4, support: 2),
  ],
  sampleCount: 4,
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);
