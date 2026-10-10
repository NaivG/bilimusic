/// 画像重排：用 [TasteProfile] 给候选歌打口味分、按分重排。
///
/// 两个消费场景：
/// - 猜你喜欢：[rankByTaste] 纯按口味分重排（没有种子概念）
/// - 漫游：[blendRoamScore] 把「像种子」和「合口味」两路信号按风格融合
///
/// 纯 Dart（分词器可注入），无服务依赖。
library;

import 'dart:math';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/roam/models/roam_style.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';
import 'package:bilimusic/features/taste/logic/text_normalizer.dart';

/// 批量算口味分：Music.key → (0, 1+]。
///
/// 分值 = 命中画像词条的权重和，按词条数做 √ 长度归一
/// （长标题天然容易命中更多词，不归一会系统性偏爱长标题）。
Future<Map<String, double>> tasteScoresFor(
  List<Music> items,
  TasteProfile profile, {
  TasteSegmenter? segmenter,
  StopwordFilter? stopFilter,
}) async {
  final result = <String, double>{};
  if (items.isEmpty || profile.isEmpty) return result;

  final seg = segmenter ?? TasteProfileBuilder.defaultSegmenter;
  final stop = stopFilter ?? await TasteProfileBuilder.defaultStopFilter();
  final weights = profile.weightMap();

  for (final m in items) {
    final tokens = normalizeTokens(stop(await seg(tasteText(m))));
    if (tokens.isEmpty) {
      result[m.key] = 0;
      continue;
    }
    final unique = tokens.toSet();
    var sum = 0.0;
    for (final t in unique) {
      sum += weights[t] ?? 0;
    }
    result[m.key] = sum / sqrt(unique.length);
  }
  return result;
}

/// 按口味分降序重排（稳定：同分保持原相对顺序）。
///
/// 用于「猜你喜欢」——现状只有 API 返回顺序，这里补上个性化排序。
Future<List<Music>> rankByTaste(
  List<Music> candidates, {
  required TasteProfile profile,
  TasteSegmenter? segmenter,
  StopwordFilter? stopFilter,
  int? limit,
}) async {
  if (candidates.length <= 1 || profile.isEmpty) {
    return limit == null ? candidates : candidates.take(limit).toList();
  }
  final scores = await tasteScoresFor(
    candidates,
    profile,
    segmenter: segmenter,
    stopFilter: stopFilter,
  );
  final ranked = List<Music>.from(candidates);
  ranked.sort((a, b) => (scores[b.key] ?? 0).compareTo(scores[a.key] ?? 0));
  return limit == null ? ranked : ranked.take(limit).toList();
}

/// 把「像不像种子」和「合不合口味」融合成一个可排序的分数。
///
/// ─────────────────────────────────────────────────────────────
/// 【设计旋钮】这里是漫游体感的唯一定调点，三个风格档的 (种子权重,
/// 口味权重, 探索偏置) 全在下面 5 行里。默认取向：
/// - similar ：几乎跟着种子走，画像只做同分微调
/// - balanced：种子、口味各半，带一点随机扰动防排布僵化
/// - explore ：距离主导、口味轻量兜底——候选本来就出自「相关视频」
///             API，天然带相似性，反种子项不压倒口味就跳不出去；
///             口味分只保证「跳远了也别跳到明显讨厌的类型」
/// 权重只要非负且每档不全为 0，调成什么样都不会破坏正确性，
/// 只改口味——放心改写，改完跑 `flutter test test/taste/` 看排序变化。
/// ─────────────────────────────────────────────────────────────
double blendRoamScore({
  required double seedSimilarity, // 0..1，越大越像种子
  required double tasteScore, // 0..1，越大越合口味
  required RoamStyle style,
  double noise = 0, // balanced 用的 [0,1) 随机扰动
}) {
  switch (style) {
    case RoamStyle.similar:
      return 0.70 * seedSimilarity + 0.30 * tasteScore;
    case RoamStyle.balanced:
      return 0.50 * seedSimilarity +
          0.45 * tasteScore +
          0.05 * noise.clamp(0.0, 1.0);
    case RoamStyle.explore:
      return 0.70 * (1 - seedSimilarity) + 0.30 * tasteScore;
  }
}
