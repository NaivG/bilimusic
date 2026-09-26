import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/roam/models/roam_style.dart';
import 'package:bilimusic/features/taste/logic/profile_ranker.dart';

import 'taste_test_helpers.dart';

void main() {
  TasteProfile profileOf(List<(String, double)> kws) => TasteProfile(
    keywords: [for (final (t, w) in kws) TasteKeyword(term: t, weight: w)],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );

  group('tasteScoresFor', () {
    test('命中画像词条得分，未命中不得分', () async {
      final profile = profileOf([('jazz', 1.0), ('piano', 0.5)]);
      final scores = await tasteScoresFor(
        [music('1', 'jazz piano'), music('2', 'heavy metal')],
        profile,
        segmenter: fakeSegmenter,
        stopFilter: identityStopFilter,
      );

      expect(scores.length, 2);
      final hit = scores.values.firstWhere((v) => v > 0);
      final miss = scores.values.firstWhere((v) => v == 0);
      expect(hit, greaterThan(0));
      expect(miss, 0);
    });

    test('空画像 → 全部 0 分（调用方降级路径）', () async {
      final scores = await tasteScoresFor(
        [music('1', 'jazz piano')],
        TasteProfile(updatedAt: DateTime.now()),
        segmenter: fakeSegmenter,
        stopFilter: identityStopFilter,
      );
      expect(scores, isEmpty);
    });
  });

  group('rankByTaste', () {
    test('口味命中多的候选排前面', () async {
      final profile = profileOf([('jazz', 1.0), ('piano', 0.8)]);
      final ranked = await rankByTaste(
        [music('a', 'heavy metal'), music('b', 'jazz piano')],
        profile: profile,
        segmenter: fakeSegmenter,
        stopFilter: identityStopFilter,
      );
      expect(ranked.first.id, 'b');
    });

    test('空画像保持原顺序', () async {
      final input = [music('a', 'one'), music('b', 'two')];
      final ranked = await rankByTaste(
        input,
        profile: TasteProfile(updatedAt: DateTime.now()),
        segmenter: fakeSegmenter,
        stopFilter: identityStopFilter,
      );
      expect(ranked.map((m) => m.id).toList(), ['a', 'b']);
    });
  });

  group('blendRoamScore（设计旋钮：方向约束，不锁具体权重）', () {
    test('similar：更像种子分更高', () {
      final hi = blendRoamScore(
        seedSimilarity: 0.9,
        tasteScore: 0.5,
        style: RoamStyle.similar,
      );
      final lo = blendRoamScore(
        seedSimilarity: 0.1,
        tasteScore: 0.5,
        style: RoamStyle.similar,
      );
      expect(hi, greaterThan(lo));
    });

    test('explore：更不像种子分更高（跳出口味圈），口味分兜底同向', () {
      final far = blendRoamScore(
        seedSimilarity: 0.1,
        tasteScore: 0.5,
        style: RoamStyle.explore,
      );
      final near = blendRoamScore(
        seedSimilarity: 0.9,
        tasteScore: 0.5,
        style: RoamStyle.explore,
      );
      expect(far, greaterThan(near));

      // 同样「不像种子」时，合口味的优先——探索不等于乱跳
      final tasty = blendRoamScore(
        seedSimilarity: 0.1,
        tasteScore: 0.9,
        style: RoamStyle.explore,
      );
      final bland = blendRoamScore(
        seedSimilarity: 0.1,
        tasteScore: 0.1,
        style: RoamStyle.explore,
      );
      expect(tasty, greaterThan(bland));
    });

    test('explore：距离差压过口味差（远而普通 > 近而对味）', () {
      // 候选出自「相关视频」API，天然带相似性，
      // explore 必须距离主导才跳得出去；口味只做轻量兜底。
      // 这条锁的是「距离权重 > 口味权重」这个方向，不锁具体数值。
      final farAndBland = blendRoamScore(
        seedSimilarity: 0.1,
        tasteScore: 0.1,
        style: RoamStyle.explore,
      );
      final nearAndTasty = blendRoamScore(
        seedSimilarity: 0.9,
        tasteScore: 0.9,
        style: RoamStyle.explore,
      );
      expect(farAndBland, greaterThan(nearAndTasty));
    });

    test('三档都随口味分单调不减', () {
      for (final style in RoamStyle.values) {
        final low = blendRoamScore(
          seedSimilarity: 0.5,
          tasteScore: 0.1,
          style: style,
        );
        final high = blendRoamScore(
          seedSimilarity: 0.5,
          tasteScore: 0.9,
          style: style,
        );
        expect(high, greaterThanOrEqualTo(low), reason: '$style 档');
      }
    });
  });
}
