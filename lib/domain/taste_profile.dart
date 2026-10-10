/// 音乐画像（Taste Profile）：用户口味的纯数据表示。
///
/// 由 `features/taste/logic/profile_builder.dart` 从播放历史 / 收藏等
/// 正信号样本构建，供漫游打分融合与「猜你喜欢」重排消费。
/// 本文件是纯共享数据模型（domain 层）：无 UI、无服务依赖。
///
/// v1 只有关键词维度；`mood`（歌词情绪档）留作后续扩展，
/// 负反馈（秒切/跳过）按设计决议 v1 不接入。
class TasteProfile {
  const TasteProfile({
    this.keywords = const [],
    this.sampleCount = 0,
    required this.updatedAt,
  });

  /// 静态版本号：画像 JSON 形状或词条清洗规则变更时 +1，读盘时旧版本直接弃用重建。
  /// （清洗规则变更也要作废旧画像——里面存的词条可能已被新规则判为噪音。）
  static const int schemaVersion = 2;

  /// Top-N 加权关键词，按 weight 降序。weight 已归一化到 (0, 1]。
  final List<TasteKeyword> keywords;

  /// 构建时参与统计的样本条数（历史 + 收藏去重后）。
  final int sampleCount;

  /// 构建/更新时间，用于 24h 节流判断。
  final DateTime updatedAt;

  bool get isEmpty => keywords.isEmpty;

  Map<String, double> get _weightMap => {
    for (final k in keywords) k.term: k.weight,
  };

  /// 查询单个词的口味权重；不在画像里返回 null。
  ///
  /// 每次调用重建 map 代价高的话由调用方自行缓存（排名场景一次构建一份）。
  double? weightOf(String term) => _weightMap[term];

  /// 批量查询用的权重表（term → weight）。
  Map<String, double> weightMap() => _weightMap;

  factory TasteProfile.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != schemaVersion) {
      // 旧版本形状不兼容：返回空画像，让服务端走重建。
      return TasteProfile(updatedAt: DateTime.fromMillisecondsSinceEpoch(0));
    }
    return TasteProfile(
      keywords: (json['keywords'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => TasteKeyword(
              term: e['term'] as String? ?? '',
              weight: (e['weight'] as num?)?.toDouble() ?? 0,
            ),
          )
          .where((k) => k.term.isNotEmpty)
          .toList(),
      sampleCount: json['sampleCount'] as int? ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int? ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'keywords': [
      for (final k in keywords) {'term': k.term, 'weight': k.weight},
    ],
    'sampleCount': sampleCount,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

/// 画像里的一个加权关键词。
class TasteKeyword {
  const TasteKeyword({required this.term, required this.weight});

  /// 归一化后的词条（分词产物：小写英文、原样中文）。
  final String term;

  /// 口味权重，(0, 1]，越大越代表长期偏好。
  final double weight;
}
