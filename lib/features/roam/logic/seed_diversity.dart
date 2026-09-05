import 'dart:math';

import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/utils/text_simhash.dart';

/// Greedy max-min diversity: 从 [pool] 中挑 [count] 个元素，使其与 [existing] 集合
/// 的最小 simhash 汉明距离最大化。
///
/// 复用 `TextSimHash.simhash` / `TextSimHash.hammingFast`，每次 hamming 比较 O(1)，
/// N+10 量级的 existing 没有性能问题。
///
/// 调用约定：
/// - `pool` 应当预先剔除 [existing] 中已有的 id（避免重复）。
/// - `existing` 为空时退化为随机抽样。
/// - 若 `pool.length <= count` 直接返回 pool 的随机洗牌。
List<Music> pickDiverse({
  required List<Music> pool,
  required List<Music> existing,
  required int count,
  required Random random,
}) {
  if (pool.isEmpty || count <= 0) return const [];
  if (pool.length <= count) {
    final shuffled = List<Music>.from(pool)..shuffle(random);
    return shuffled;
  }
  if (existing.isEmpty) {
    final shuffled = List<Music>.from(pool)..shuffle(random);
    return shuffled.take(count).toList();
  }

  final existingHashes = existing
      .map((m) => TextSimHash.simhash(TextSimHash.musicToText(m)))
      .toList();

  final scored = pool.map((c) {
    final ch = TextSimHash.simhash(TextSimHash.musicToText(c));
    final minDist = existingHashes
        .map((eh) => TextSimHash.hammingFast(ch, eh))
        .reduce((a, b) => a < b ? a : b);
    return MapEntry(c, minDist);
  }).toList()..sort((a, b) => b.value.compareTo(a.value));

  return scored.take(count).map((e) => e.key).toList();
}
