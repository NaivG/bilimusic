import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/domain/bili_item.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/roam/models/roam_style.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/domain/music_category.dart';
import 'package:bilimusic/features/roam/logic/text_simhash.dart';

/// 漫游服务：根据 seed 歌拉相关音乐、按 simhash 排序、按 RoamStyle 挑选。
///
/// 由 PlayerCoordinator 在 `currentIndex` 接近队列末尾时调用。
/// 返回的 Music 列表会被 `addAllToPlaylist` 自动按 (bvid, cid) 去重。
class RoamingService {
  RoamingService({
    required BiliClient client,
    required PlaylistService playlistService,
    Random? random,
  }) : _client = client,
       _playlistService = playlistService,
       _random = random ?? Random();

  final BiliClient _client;
  final PlaylistService _playlistService;
  final Random _random;

  /// 拉一批候选候选。
  ///
  /// [size] 默认 3，避免一次性塞太多打断 crossfade 节奏。
  /// 失败或 0 候选时返回 `[]`，调用方据此降级。
  Future<List<Music>> fetchBatch({
    required Music seed,
    required RoamStyle style,
    int size = 3,
  }) async {
    try {
      final raw = await _client.get(
        '/x/web-interface/archive/related',
        query: {'bvid': seed.id},
      );
      if (raw is! List) return const [];

      final candidates = <Music>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final tid = item['tid'] as int?;
        if (!isMusicCategory(tid)) continue;

        final music = Music.fromArchiveJson(Map<String, dynamic>.from(item));
        if (music.id.isEmpty) continue;

        candidates.add(music);
      }

      return _pick(candidates, seed: seed, style: style, size: size);
    } on BiliException catch (e) {
      debugPrint('[RoamingService] fetch failed for ${seed.id}: $e');
      return const [];
    } catch (e) {
      debugPrint('[RoamingService] unexpected error: $e');
      return const [];
    }
  }

  /// 按 (bvid, cid) 去重 + simhash 排序 + 按 style 挑选 size 个。
  List<Music> _pick(
    List<Music> candidates, {
    required Music seed,
    required RoamStyle style,
    required int size,
  }) {
    if (candidates.isEmpty) return const [];

    // dedup: 排除当前队列和播放历史
    final existing = <String>{
      for (final m in _playlistService.currentPlaylist.value) m.key,
      for (final m in _playlistService.playHistorySnapshot) m.key,
    };
    final fresh = candidates
        .where((m) => !existing.contains(m.key))
        .toList();
    if (fresh.isEmpty) return const [];

    // simhash 排序
    final seedHash = TextSimHash.simhash(TextSimHash.musicToText(seed));
    fresh.sort((a, b) {
      final ha = TextSimHash.simhash(TextSimHash.musicToText(a));
      final hb = TextSimHash.simhash(TextSimHash.musicToText(b));
      return TextSimHash.hammingFast(
        seedHash,
        ha,
      ).compareTo(TextSimHash.hammingFast(seedHash, hb));
    });

    switch (style) {
      case RoamStyle.similar:
        return fresh.take(size).toList();
      case RoamStyle.balanced:
        // 随机洗牌后取 size 个，给相似/多样性都留点空间
        final shuffled = List<Music>.from(fresh)..shuffle(_random);
        return shuffled.take(size).toList();
      case RoamStyle.explore:
        // 反向排序后取 size 个（最不像的优先）
        return fresh.reversed.take(size).toList();
    }
  }

  /// 预取一轮候选的推荐（用于 onboarding step A.5/B）。
  ///
  /// - 并发调用 [fetchBatch]（默认 `balanced` 风格以最大化多样性）。
  /// - 全部失败且 [candidates] 长度足够时 fallback = 把 candidates 本身当候选
  ///   （适用于 tempQueue 很小的低数据模式）。
  /// - 结果已按 (id, cid) 去重并随机洗牌。
  Future<List<Music>> prefetchRound({
    required List<Music> candidates,
    int maxPerRound = 5,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (candidates.isEmpty) return const [];

    final futures = candidates.map((c) async {
      try {
        return await fetchBatch(
          seed: c,
          style: RoamStyle.balanced,
          size: maxPerRound,
        ).timeout(timeout);
      } catch (_) {
        return const <Music>[];
      }
    }).toList();

    final results = await Future.wait(futures);
    final merged = results.expand((l) => l).toList();
    final deduped = _dedupByIdCid(merged);
    deduped.shuffle(_random);

    if (deduped.isEmpty && candidates.length >= maxPerRound) {
      return candidates.take(maxPerRound).toList();
    }
    return deduped.take(maxPerRound).toList();
  }

  /// 从多颗种子 fetch 推荐并合并。
  ///
  /// - 每颗种子 fetch size = `ceil(totalSize / seeds.length)`。
  /// - 内部已按 (id, cid) 去重。
  /// - 接受部分失败（个别种子 fetch 失败不会中断其他种子）。
  Future<List<Music>> fetchMultiSeed({
    required List<Music> seeds,
    required RoamStyle style,
    required int totalSize,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (seeds.isEmpty || totalSize <= 0) return const [];

    final perSeed = (totalSize / seeds.length).ceil();
    final futures = seeds.map((s) async {
      try {
        return await fetchBatch(
          seed: s,
          style: style,
          size: perSeed,
        ).timeout(timeout);
      } catch (_) {
        return const <Music>[];
      }
    }).toList();

    final results = await Future.wait(futures);
    final merged = results.expand((l) => l).toList();
    final deduped = _dedupByIdCid(merged);
    return deduped.take(totalSize).toList();
  }

  /// 按 (id, cid) 去重。用于合并多个 [fetchBatch] 结果。
  List<Music> _dedupByIdCid(List<Music> list) {
    final seen = <String>{};
    final out = <Music>[];
    for (final m in list) {
      if (seen.add(m.key)) out.add(m);
    }
    return out;
  }

  /// 把 bvid 解析回完整的 [Music]。
  ///
  /// 仅用于导入流程：先用此方法验证种子视频仍可访问，再决定是否走
  /// [fetchMultiSeed]（否则视频已失效/删除时 recs 会一连串失败，错误信息
  /// 也很难定位根因）。
  ///
  /// 总是返回第一个分 P（导出的种子 cid 为空，page 索引足以覆盖大部分场景）。
  /// 视频整体不可访问时抛 [BiliException]，由调用方决定如何展示给用户。
  Future<Music> resolveSeed(String bvid) async {
    final data = await _client.get(
      '/x/web-interface/view',
      query: {'bvid': bvid},
    );
    if (data is! Map<String, dynamic>) {
      throw BiliApiException(-1, '无效的视频详情响应: $bvid');
    }
    final biliItem = BiliItem.fromViewApi(data);
    if (biliItem.pages.isEmpty) {
      throw BiliApiException(-1, '视频无可用分P: $bvid');
    }
    return biliItem.pages.first;
  }
}
