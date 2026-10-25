import 'dart:math' as math;

import 'package:bilimusic/domain/taste_profile.dart';

/// 画像关系图的纯 Dart 布局。
///
/// 输入 [TasteProfile] 的关键词/共现边，输出固定画布内的节点坐标。
/// 不依赖 Flutter，方便单测；渲染层只负责把坐标画出来。
class TasteGraphLayout {
  TasteGraphLayout({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  }) : _byTerm = {for (final n in nodes) n.term: n};

  factory TasteGraphLayout.empty({
    required double width,
    required double height,
  }) => TasteGraphLayout(
    nodes: const [],
    edges: const [],
    width: width,
    height: height,
  );

  /// 按权重降序排列的节点。
  final List<TasteGraphNode> nodes;

  /// 按 [TasteEdge.compare] 排序的边，两端都指向 [nodes] 里的实例。
  final List<TasteGraphEdge> edges;

  final double width;
  final double height;
  final Map<String, TasteGraphNode> _byTerm;

  bool get isEmpty => nodes.isEmpty;
  bool get hasEdges => edges.isNotEmpty;

  TasteGraphNode? nodeOf(String term) => _byTerm[term];

  /// 与 [term] 直接相连的边，保持强度降序。
  List<TasteGraphEdge> edgesOf(String term) => [
    for (final e in edges)
      if (e.a.term == term || e.b.term == term) e,
  ];

  /// 把画像压成一张可绘制的关系图。
  ///
  /// [maxNodes] 只取权重最高的词条，控制手机上的视觉密度；
  /// [maxEdgesPerNode] 再按节点截断一次，避免数据层异常时出现毛球。
  factory TasteGraphLayout.compute(
    TasteProfile profile, {
    required double width,
    required double height,
    int maxNodes = 32,
    int maxEdgesPerNode = 5,
    int iterations = 240,
  }) {
    if (profile.isEmpty ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return TasteGraphLayout.empty(width: width, height: height);
    }

    final sorted = List<TasteKeyword>.from(profile.keywords)
      ..sort((a, b) {
        final byWeight = b.weight.compareTo(a.weight);
        return byWeight != 0 ? byWeight : a.term.compareTo(b.term);
      });
    final selected = sorted
        .take(maxNodes <= 0 ? 1 : maxNodes)
        .toList(growable: false);
    final selectedTerms = {for (final k in selected) k.term};

    final candidates = <TasteEdge>[
      for (final e in profile.edges)
        if (e.a != e.b &&
            selectedTerms.contains(e.a) &&
            selectedTerms.contains(e.b))
          e,
    ]..sort(TasteEdge.compare);

    final degree = <String, int>{};
    final keptEdges = <TasteEdge>[];
    final edgeLimit = maxEdgesPerNode <= 0 ? 0 : maxEdgesPerNode;
    final perNode = <String, int>{};
    for (final edge in candidates) {
      if (edgeLimit == 0) break;
      final degA = perNode[edge.a] ?? 0;
      final degB = perNode[edge.b] ?? 0;
      if (degA >= edgeLimit || degB >= edgeLimit) continue;
      keptEdges.add(edge);
      perNode[edge.a] = degA + 1;
      perNode[edge.b] = degB + 1;
      degree[edge.a] = (degree[edge.a] ?? 0) + 1;
      degree[edge.b] = (degree[edge.b] ?? 0) + 1;
    }

    final positions = _initialPositions(selected, width, height);
    if (selected.length > 1) {
      _forceDirected(
        positions,
        keptEdges,
        width: width,
        height: height,
        iterations: keptEdges.isEmpty ? math.min(iterations, 160) : iterations,
      );
    }
    _fitToBounds(positions, width: width, height: height);

    // 先算半径，再把所有圆心收进画布，保证圆本身不被裁掉。
    var maxRadius = 0.0;
    final radii = <String, double>{};
    for (final k in selected) {
      final deg = degree[k.term] ?? 0;
      final radius =
          (4.5 +
                  7.0 * k.weight.clamp(0.0, 1.0).toDouble() +
                  1.2 * math.sqrt(deg))
              .clamp(5.0, 14.0)
              .toDouble();
      radii[k.term] = radius;
      maxRadius = math.max(maxRadius, radius);
    }
    final inset = maxRadius + 2;
    final minX = math.min(inset, width / 2);
    final maxX = math.max(minX, width - inset);
    final minY = math.min(inset, height / 2);
    final maxY = math.max(minY, height - inset);
    for (final p in positions.values) {
      p.x = p.x.clamp(minX, maxX).toDouble();
      p.y = p.y.clamp(minY, maxY).toDouble();
    }

    final nodes = <TasteGraphNode>[
      for (final k in selected)
        TasteGraphNode(
          keyword: k,
          x: positions[k.term]!.x,
          y: positions[k.term]!.y,
          radius: radii[k.term]!,
          degree: degree[k.term] ?? 0,
        ),
    ];
    final byTerm = {for (final n in nodes) n.term: n};
    final edges = <TasteGraphEdge>[
      for (final e in keptEdges)
        TasteGraphEdge(edge: e, a: byTerm[e.a]!, b: byTerm[e.b]!),
    ];
    return TasteGraphLayout(
      nodes: nodes,
      edges: edges,
      width: width,
      height: height,
    );
  }

  /// 黄金角螺旋：权重高的词靠近中心，初始分布均匀且完全确定。
  static Map<String, _MutablePoint> _initialPositions(
    List<TasteKeyword> selected,
    double width,
    double height,
  ) {
    final centerX = width / 2;
    final centerY = height / 2;
    final maxR = math.min(width, height) * 0.30;
    final positions = <String, _MutablePoint>{};
    final n = selected.length;
    for (var i = 0; i < n; i++) {
      final k = selected[i];
      final r = n == 1 ? 0.0 : maxR * math.sqrt((i + 0.5) / n);
      final theta = i * 2.399963229728653;
      positions[k.term] = _MutablePoint(
        centerX + r * math.cos(theta),
        centerY + r * math.sin(theta),
      );
    }
    return positions;
  }

  /// Fruchterman-Reingold：节点两两排斥，边把两端拉近。
  ///
  /// 规模只有几十个节点，O(n²) 足够；固定迭代次数、无随机数，
  /// 同一份画像在同一尺寸下每次都得到相同布局。
  static void _forceDirected(
    Map<String, _MutablePoint> positions,
    List<TasteEdge> edges, {
    required double width,
    required double height,
    required int iterations,
  }) {
    final terms = positions.keys.toList(growable: false);
    final n = terms.length;
    if (n <= 1 || iterations <= 0) return;

    final area = width * height;
    final k = math.sqrt(area / n) * 0.8;
    if (k <= 0) return;
    final centerX = width / 2;
    final centerY = height / 2;
    final pad = math.min(16.0, math.min(width, height) * 0.08);
    final displacement = <String, _MutablePoint>{};

    for (var iter = 0; iter < iterations; iter++) {
      for (final term in terms) {
        displacement[term] = _MutablePoint.zero();
      }

      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final pa = positions[terms[i]]!;
          final pb = positions[terms[j]]!;
          var dx = pa.x - pb.x;
          var dy = pa.y - pb.y;
          var dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 0.01) {
            dx = 1;
            dy = 0;
            dist = 0.01;
          }
          final force = (k * k) / dist;
          final ux = dx / dist;
          final uy = dy / dist;
          displacement[terms[i]]!.add(ux * force, uy * force);
          displacement[terms[j]]!.add(-ux * force, -uy * force);
        }
      }

      for (final edge in edges) {
        final pa = positions[edge.a]!;
        final pb = positions[edge.b]!;
        var dx = pa.x - pb.x;
        var dy = pa.y - pb.y;
        var dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 0.01) {
          dx = 1;
          dy = 0;
          dist = 0.01;
        }
        final strength = 0.35 + 0.65 * edge.weight.clamp(0.0, 1.0).toDouble();
        final force = (dist * dist / k) * strength;
        final ux = dx / dist;
        final uy = dy / dist;
        displacement[edge.a]!.add(-ux * force, -uy * force);
        displacement[edge.b]!.add(ux * force, uy * force);
      }

      final temp =
          math.max(width, height) * 0.08 * (1 - iter / iterations) + 0.5;
      for (final term in terms) {
        final p = positions[term]!;
        final d = displacement[term]!;
        // 弱向心重力：孤立节点不会飘到画布边缘。
        d.add((centerX - p.x) * 0.012, (centerY - p.y) * 0.012);
        final len = math.sqrt(d.x * d.x + d.y * d.y);
        if (len < 0.0001) continue;
        final limited = math.min(len, temp);
        p.x = (p.x + d.x / len * limited)
            .clamp(pad, math.max(pad, width - pad))
            .toDouble();
        p.y = (p.y + d.y / len * limited)
            .clamp(pad, math.max(pad, height - pad))
            .toDouble();
      }
    }
  }

  /// 等比缩放并居中，让内容尽量填满画布但不改变拓扑比例。
  static void _fitToBounds(
    Map<String, _MutablePoint> positions, {
    required double width,
    required double height,
  }) {
    if (positions.isEmpty) return;

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final p in positions.values) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }

    final pad = math.min(24.0, math.min(width, height) * 0.08);
    final availW = math.max(1.0, width - 2 * pad);
    final availH = math.max(1.0, height - 2 * pad);
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    var scale = double.infinity;
    if (spanX > 0.01) scale = math.min(scale, availW / spanX);
    if (spanY > 0.01) scale = math.min(scale, availH / spanY);
    if (!scale.isFinite || scale <= 0) scale = 1.0;
    scale = math.min(scale, 1.4);

    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final targetX = width / 2;
    final targetY = height / 2;
    for (final p in positions.values) {
      p.x = targetX + (p.x - cx) * scale;
      p.y = targetY + (p.y - cy) * scale;
    }
  }
}

/// 布局后的一个节点。坐标是画布局部坐标，单位与 [TasteGraphLayout.width] 一致。
class TasteGraphNode {
  const TasteGraphNode({
    required this.keyword,
    required this.x,
    required this.y,
    required this.radius,
    required this.degree,
  });

  final TasteKeyword keyword;
  final double x;
  final double y;
  final double radius;
  final int degree;

  String get term => keyword.term;
  double get weight => keyword.weight;
  int get df => keyword.df;
}

/// 布局后的边，直接持有两端节点，绘制时不用再查表。
class TasteGraphEdge {
  const TasteGraphEdge({required this.edge, required this.a, required this.b});

  final TasteEdge edge;
  final TasteGraphNode a;
  final TasteGraphNode b;

  TasteGraphNode other(TasteGraphNode node) => identical(node, a) ? b : a;
}

class _MutablePoint {
  _MutablePoint(this.x, this.y);
  _MutablePoint.zero() : x = 0, y = 0;

  double x;
  double y;

  void add(double dx, double dy) {
    x += dx;
    y += dy;
  }
}
