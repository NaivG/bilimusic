import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/domain/taste_profile.dart';

void main() {
  group('TasteProfile JSON 往返', () {
    test('toJson → fromJson 保持内容', () {
      final profile = TasteProfile(
        keywords: const [
          TasteKeyword(term: '爵士', weight: 1.0),
          TasteKeyword(term: '钢琴', weight: 0.5),
        ],
        sampleCount: 12,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final restored = TasteProfile.fromJson(profile.toJson());
      expect(restored.keywords.length, 2);
      expect(restored.keywords[0].term, '爵士');
      expect(restored.keywords[0].weight, 1.0);
      expect(restored.keywords[1].term, '钢琴');
      expect(restored.keywords[1].weight, 0.5);
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

    test('weightMap / weightOf 查询', () {
      final profile = TasteProfile(
        keywords: const [TasteKeyword(term: 'jazz', weight: 0.8)],
        updatedAt: DateTime.now(),
      );
      expect(profile.weightOf('jazz'), 0.8);
      expect(profile.weightOf('rock'), isNull);
      expect(profile.weightMap(), {'jazz': 0.8});
    });

    test('空关键词 → isEmpty', () {
      expect(TasteProfile(updatedAt: DateTime.now()).isEmpty, true);
    });
  });
}
