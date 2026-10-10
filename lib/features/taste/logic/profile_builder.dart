import 'dart:math' as math;

import 'package:snownlp/snownlp.dart' as snow;

import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/text_normalizer.dart';

/// 画像语料的分词函数：文本 → token 列表（未清洗）。
///
/// 可注入：测试里换成假分词器，`profile_builder` 的加权逻辑就与
/// snownlp 模型完全解耦（模型 7MB+，测试不该背它）。
typedef TasteSegmenter = Future<List<String>> Function(String text);

/// 停用词过滤：token 列表 → 过滤后的 token 列表（同步）。
typedef StopwordFilter = List<String> Function(List<String> tokens);

/// 一条画像样本：一段语料 + 权重（来源强度）。
class ProfileSample {
  const ProfileSample({required this.text, this.weight = 1.0});

  /// 语料文本（[tasteText] 的输出）。
  final String text;

  /// 样本权重：历史新鲜度衰减、收藏加成等由服务层算好传进来。
  final double weight;
}

/// 加权词频画像构建器（纯逻辑，分词器可注入）。
///
/// 算法（v1 刻意选它而不是 TextRank）：
/// ```
/// 每样本分词 → 去停用词 → normalizeTokens
/// score[term] += sampleWeight × (1 + ln(count))   // 次线性词频
/// df[term]    += 1                                 // 文档频率
/// 保留 df ≥ 2 或 forcedTerms 里的词 → 取 topN → 按最大分归一化
/// ```
/// 原因：TextRank 在 < 20 条语料上边权噪声很大（冷启动必经阶段），
/// 而加权词频在任意样本量下都稳定、可解释、确定性强。
/// 语料够大之后要换 TextRank/TF-IDF，只动这一个类。
class TasteProfileBuilder {
  TasteProfileBuilder({TasteSegmenter? segmenter, StopwordFilter? stopFilter})
    : _segmenter = segmenter ?? defaultSegmenter,
      _stopFilter = stopFilter;

  final TasteSegmenter _segmenter;
  StopwordFilter? _stopFilter;

  /// 构建画像。[forcedTexts] 是服务层直接认定的口味语料（如用户自建
  /// 歌单名、歌单标签名）：走同一套分词清洗，但产出的词条跳过 df 过滤
  /// 并获得 [forcedBoost] 的加分（用户亲手写下的词就是最高权重信号）。
  Future<TasteProfile> build(
    List<ProfileSample> samples, {
    List<String> forcedTexts = const [],
    int topN = 48,
    double forcedBoost = 2.5,
    DateTime? now,
  }) async {
    final updatedAt = now ?? DateTime.now();
    if (samples.isEmpty && forcedTexts.isEmpty) {
      return TasteProfile(updatedAt: updatedAt);
    }

    final stopFilter = _stopFilter ??= await defaultStopFilter();

    final score = <String, double>{};
    final df = <String, int>{};

    for (final s in samples) {
      if (s.text.trim().isEmpty) continue;
      final tokens = normalizeTokens(stopFilter(await _segmenter(s.text)));
      if (tokens.isEmpty) continue;

      final counts = <String, int>{};
      for (final t in tokens) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
      counts.forEach((term, count) {
        score[term] = (score[term] ?? 0) + s.weight * (1 + math.log(count));
        df[term] = (df[term] ?? 0) + 1;
      });
    }

    for (final text in forcedTexts) {
      final tokens = normalizeTokens(stopFilter(await _segmenter(text)));
      for (final term in tokens.toSet()) {
        score[term] = (score[term] ?? 0) + forcedBoost;
        df[term] = 1 << 20; // 强制保留，绕过 df 过滤
      }
    }

    final kept = score.entries.where((e) => (df[e.key] ?? 0) >= 2).toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });

    if (kept.isEmpty) {
      return TasteProfile(sampleCount: samples.length, updatedAt: updatedAt);
    }

    final top = kept.take(topN).toList();
    final maxScore = top.first.value;
    return TasteProfile(
      keywords: [
        for (final e in top)
          TasteKeyword(term: e.key, weight: e.value / maxScore),
      ],
      sampleCount: samples.length,
      updatedAt: updatedAt,
    );
  }

  // ── 默认分词器：snownlp（seg + 停用词表） ──
  // 公开给 profile_ranker 复用，保证「建画像」与「排名」同一套清洗。

  static Future<List<String>> defaultSegmenter(String text) => snow.seg(text);

  static Future<StopwordFilter> defaultStopFilter() async {
    final sw = await snow.stopwords;
    return (tokens) => sw.filterStop(tokens);
  }
}
