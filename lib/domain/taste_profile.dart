/// 音乐画像（Taste Profile）：用户口味的纯数据表示。
///
/// 由 `features/taste/logic/profile_builder.dart` 从播放历史 / 收藏等
/// 正信号样本构建，供漫游打分融合与「猜你喜欢」重排消费。
/// 本文件是纯共享数据模型（domain 层）：无 UI、无服务依赖。
///
/// v3 在关键词之外增加文档频率与词-词共现边，供画像关系图渲染；
/// `mood`（歌词情绪档）留作后续扩展，负反馈（秒切/跳过）按设计决议
/// v1 不接入。
class TasteProfile {
  const TasteProfile({
    this.keywords = const [],
    this.edges = const [],
    this.sampleCount = 0,
    required this.updatedAt,
  });

  /// 静态版本号：画像 JSON 形状或词条清洗规则变更时 +1，读盘时旧版本直接弃用重建。
  /// （清洗规则变更也要作废旧画像——里面存的词条可能已被新规则判为噪音。）
  static const int schemaVersion = 3;

  /// Top-N 加权关键词，按 weight 降序。weight 已归一化到 (0, 1]。
  final List<TasteKeyword> keywords;

  /// 关键词之间的无向共现边，按 weight 降序。
  ///
  /// 两端必须都在 [keywords] 里；[TasteEdge.a] / [TasteEdge.b] 按字典序排列。
  final List<TasteEdge> edges;

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

  /// 查询与 [term] 直接相连的边，保持画像里的 weight 降序。
  List<TasteEdge> edgesOf(String term) => [
    for (final e in edges)
      if (e.a == term || e.b == term) e,
  ];

  factory TasteProfile.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != schemaVersion) {
      // 旧版本形状不兼容：返回空画像，让服务端走重建。
      return TasteProfile(updatedAt: DateTime.fromMillisecondsSinceEpoch(0));
    }
    final keywords = (json['keywords'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (e) => TasteKeyword(
            term: e['term'] as String? ?? '',
            weight: (e['weight'] as num?)?.toDouble() ?? 0,
            df: (e['df'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((k) => k.term.isNotEmpty)
        .toList();
    final terms = {for (final k in keywords) k.term};
    final edges = <TasteEdge>[];
    final seen = <String>{};
    for (final raw in json['edges'] as List? ?? const []) {
      if (raw is! Map) continue;
      var a = (raw['a'] as String? ?? '').trim();
      var b = (raw['b'] as String? ?? '').trim();
      if (a.isEmpty || b.isEmpty || a == b) continue;
      if (!terms.contains(a) || !terms.contains(b)) continue;
      if (a.compareTo(b) > 0) {
        final tmp = a;
        a = b;
        b = tmp;
      }
      final weight = ((raw['weight'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0)
          .toDouble();
      final support = (raw['support'] as num?)?.toInt() ?? 0;
      if (weight <= 0 || support <= 0) continue;
      if (!seen.add('$a\u0000$b')) continue;
      edges.add(TasteEdge(a: a, b: b, weight: weight, support: support));
    }
    edges.sort(TasteEdge.compare);
    return TasteProfile(
      keywords: keywords,
      edges: edges,
      sampleCount: json['sampleCount'] as int? ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int? ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'keywords': [
      for (final k in keywords)
        {'term': k.term, 'weight': k.weight, 'df': k.df},
    ],
    'edges': [
      for (final e in edges)
        {'a': e.a, 'b': e.b, 'weight': e.weight, 'support': e.support},
    ],
    'sampleCount': sampleCount,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

/// 画像里的一个加权关键词。
class TasteKeyword {
  const TasteKeyword({required this.term, required this.weight, this.df = 0});

  /// 归一化后的词条（分词产物：小写英文、原样中文）。
  final String term;

  /// 口味权重，(0, 1]，越大越代表长期偏好。
  final double weight;

  /// 构建时包含该词的歌曲样本数；仅来自歌单名/标签的词为 0。
  final int df;
}

/// 两个关键词之间的无向共现关系。
class TasteEdge {
  const TasteEdge({
    required this.a,
    required this.b,
    required this.weight,
    required this.support,
  });

  /// 字典序较小的端点。
  final String a;

  /// 字典序较大的端点。
  final String b;

  /// 共现强度 (0, 1]：按歌曲文档频率算的 Jaccard。
  final double weight;

  /// 两个词共同出现的歌曲样本数。
  final int support;

  /// 关系图/JSON 共用的稳定顺序：weight 降序、support 降序、端点字典序。
  static int compare(TasteEdge x, TasteEdge y) {
    final byWeight = y.weight.compareTo(x.weight);
    if (byWeight != 0) return byWeight;
    final bySupport = y.support.compareTo(x.support);
    if (bySupport != 0) return bySupport;
    final byA = x.a.compareTo(y.a);
    return byA != 0 ? byA : x.b.compareTo(y.b);
  }
}
