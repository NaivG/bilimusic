import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/domain/taste_profile.dart';

void main() {
  group('TasteProfile JSON 往返', () {
    test('toJson → fromJson 保持关键词、df 与共现边', () {
      final profile = TasteProfile(
        keywords: const [
          TasteKeyword(term: '爵士', weight: 1.0, df: 8),
          TasteKeyword(term: '钢琴', weight: 0.5, df: 5),
        ],
        edges: const [TasteEdge(a: '爵士', b: '钢琴', weight: 0.5, support: 4)],
        sampleCount: 12,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final restored = TasteProfile.fromJson(profile.toJson());
      expect(restored.keywords.length, 2);
      expect(restored.keywords[0].term, '爵士');
      expect(restored.keywords[0].weight, 1.0);
      expect(restored.keywords[0].df, 8);
      expect(restored.keywords[1].term, '钢琴');
      expect(restored.keywords[1].weight, 0.5);
      expect(restored.keywords[1].df, 5);
      expect(restored.edges.length, 1);
      expect(restored.edges.single.a, '爵士');
      expect(restored.edges.single.b, '钢琴');
      expect(restored.edges.single.weight, 0.5);
      expect(restored.edges.single.support, 4);
      expect(restored.sampleCount, 12);
      expect(restored.updatedAt, profile.updatedAt);
    });

    test('schema 版本不符 → 返回空画像（epoch 时间戳），调用方当没有处理', () {
      final restored = TasteProfile.fromJson({
        'version': TasteProfile.schemaVersion + 1,
        'keywords': [
          {'term': '爵士', 'weight': 1.0},
        ],
        'sampleCount': 3,
        'updatedAt': 1700000000000,
      });

      expect(restored.isEmpty, true);
      expect(restored.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('fromJson 丢弃孤立/自环/重复边，并规范端点顺序', () {
      final restored = TasteProfile.fromJson({
        'version': TasteProfile.schemaVersion,
        'keywords': [
          {'term': 'jazz', 'weight': 1.0, 'df': 2},
          {'term': 'piano', 'weight': 0.5, 'df': 2},
        ],
        'edges': [
          {'a': 'piano', 'b': 'jazz', 'weight': 0.5, 'support': 2},
          {'a': 'jazz', 'b': 'missing', 'weight': 0.9, 'support': 9},
          {'a': 'jazz', 'b': 'jazz', 'weight': 0.9, 'support': 9},
          {'a': 'jazz', 'b': 'piano', 'weight': 0.5, 'support': 2},
        ],
        'sampleCount': 4,
        'updatedAt': 1700000000000,
      });

      expect(restored.edges.length, 1);
      expect(restored.edges.single.a, 'jazz');
      expect(restored.edges.single.b, 'piano');
    });

    test('weightMap / weightOf 查询', () {
      final profile = TasteProfile(
        keywords: const [TasteKeyword(term: 'jazz', weight: 0.8)],
        updatedAt: DateTime.now(),
      );
      expect(profile.weightOf('jazz'), 0.8);
      expect(profile.weightOf('rock'), isNull);
      expect(profile.weightMap(), {'jazz': 0.8});
    });

    test('edgesOf 只返回直接相连的边', () {
      final profile = TasteProfile(
        keywords: const [
          TasteKeyword(term: 'jazz', weight: 1.0),
          TasteKeyword(term: 'piano', weight: 0.8),
          TasteKeyword(term: 'rock', weight: 0.6),
        ],
        edges: const [
          TasteEdge(a: 'jazz', b: 'piano', weight: 0.5, support: 3),
          TasteEdge(a: 'jazz', b: 'rock', weight: 0.2, support: 2),
        ],
        updatedAt: DateTime.now(),
      );

      expect(profile.edgesOf('jazz').length, 2);
      expect(profile.edgesOf('piano').length, 1);
      expect(profile.edgesOf('nope'), isEmpty);
    });

    test('空关键词 → isEmpty', () {
      expect(TasteProfile(updatedAt: DateTime.now()).isEmpty, true);
    });
  });
}
