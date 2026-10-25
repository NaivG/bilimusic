import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/taste_graph_layout.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 内嵌在音乐画像页里的口味关系图。
///
/// 节点是画像关键词，节点越大权重越高；边是同歌共现关系，线越粗越强。
/// 点击圆点进入「聚焦」状态：只高亮它和一跳邻居，并在下方展开关联词。
/// 图本身是增强视图，完整词条列表仍由页面下方的 chips 提供。
class TasteGraphCard extends StatefulWidget {
  const TasteGraphCard({super.key, required this.profile});

  final TasteProfile profile;

  @override
  State<TasteGraphCard> createState() => _TasteGraphCardState();
}

class _TasteGraphCardState extends State<TasteGraphCard> {
  String? _selected;
  TasteGraphLayout? _layout;
  TasteProfile? _layoutProfile;
  double? _layoutWidth;
  double? _layoutHeight;

  @override
  void didUpdateWidget(covariant TasteGraphCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.profile, widget.profile)) return;
    _layout = null;
    _layoutProfile = null;
    final selected = _selected;
    if (selected != null && widget.profile.weightOf(selected) == null) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;
    if (profile.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('口味关系图', style: theme.textTheme.titleMedium),
                ),
                if (_selected != null)
                  TextButton(
                    onPressed: () => setState(() => _selected = null),
                    child: const Text('清除'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '节点越大权重越高，连线越粗表示越常在同一首歌里一起出现。'
              '点击圆点查看关联。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (!width.isFinite || width < 80) {
                  return const SizedBox.shrink();
                }
                if (profile.edges.isEmpty) {
                  return _buildEmptyState(context);
                }
                final height = (width * 0.9).clamp(280.0, 420.0).toDouble();
                final layout = _ensureLayout(width, height);
                if (layout.edges.isEmpty) {
                  return _buildEmptyState(context);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCanvas(context, layout, width, height),
                    if (profile.keywords.length > layout.nodes.length) ...[
                      const SizedBox(height: 8),
                      Text(
                        '图中显示权重最高的 ${layout.nodes.length} 个词条，'
                        '完整列表见下方。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (layout.edges.length < 3) ...[
                      const SizedBox(height: 6),
                      Text(
                        '当前关系还比较稀疏，继续听歌会自动补充。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_selected != null) ...[
                      const SizedBox(height: 10),
                      _buildDetail(context, layout, _selected!),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  TasteGraphLayout _ensureLayout(double width, double height) {
    final cached = _layout;
    if (cached != null &&
        identical(_layoutProfile, widget.profile) &&
        _layoutWidth == width &&
        _layoutHeight == height) {
      return cached;
    }
    final layout = TasteGraphLayout.compute(
      widget.profile,
      width: width,
      height: height,
      maxNodes: width < 420 ? 24 : (width < 720 ? 32 : 40),
      maxEdgesPerNode: 3,
      iterations: 220,
    );
    _layout = layout;
    _layoutProfile = widget.profile;
    _layoutWidth = width;
    _layoutHeight = height;
    return layout;
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 140,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub, size: 28, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('关系还不够清晰', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '画像词条之间还没有稳定的共现关系。多听几首、收藏一些歌，关系图会自动长出来。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    TasteGraphLayout layout,
    double width,
    double height,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          '口味关系图，${layout.nodes.length} 个词条，${layout.edges.length} 条关联。点击圆点查看详情。',
      child: Container(
        key: const Key('taste_graph_canvas'),
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final node = _hitTest(layout, details.localPosition);
              setState(() {
                _selected = node == null || node.term == _selected
                    ? null
                    : node.term;
              });
            },
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _TasteGraphPainter(
                  layout: layout,
                  selectedTerm: _selected,
                  primary: scheme.primary,
                  secondary: scheme.secondary,
                  onSurface: scheme.onSurface,
                  onSurfaceVariant: scheme.onSurfaceVariant,
                  surface: scheme.surface,
                  outline: scheme.outline,
                  fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TasteGraphNode? _hitTest(TasteGraphLayout layout, Offset position) {
    TasteGraphNode? best;
    var bestDistance = double.infinity;
    for (final node in layout.nodes) {
      final distance = (Offset(node.x, node.y) - position).distance;
      final hitRadius = math.max(node.radius + 12, 20.0);
      if (distance <= hitRadius && distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }
    return best;
  }

  Widget _buildDetail(
    BuildContext context,
    TasteGraphLayout layout,
    String term,
  ) {
    final theme = Theme.of(context);
    final node = layout.nodeOf(term);
    if (node == null) return const SizedBox.shrink();
    final related = layout.edgesOf(term);
    final source = node.df > 0 ? '出现在 ${node.df} 首歌' : '来自歌单 / 标签';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: '关闭',
              ),
            ],
          ),
          Text(
            '口味权重 ${node.weight.toStringAsFixed(2)} · $source',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (related.isEmpty)
            Text(
              '暂未发现稳定的共现词。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text('常一起出现', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final edge in related.take(5))
                  ActionChip(
                    label: Text(
                      '${_otherTerm(edge, term)} · ${edge.edge.support} 首',
                    ),
                    onPressed: () =>
                        setState(() => _selected = _otherTerm(edge, term)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _otherTerm(TasteGraphEdge edge, String term) =>
      edge.a.term == term ? edge.b.term : edge.a.term;
}

class _TasteGraphPainter extends CustomPainter {
  _TasteGraphPainter({
    required this.layout,
    required this.selectedTerm,
    required this.primary,
    required this.secondary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surface,
    required this.outline,
    required this.fontFamily,
    required this.textScaler,
  });

  final TasteGraphLayout layout;
  final String? selectedTerm;
  final Color primary;
  final Color secondary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surface;
  final Color outline;
  final String? fontFamily;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) return;

    final selected = selectedTerm == null ? null : layout.nodeOf(selectedTerm!);
    final focusTerms = <String>{};
    if (selected != null) {
      focusTerms.add(selected.term);
      for (final edge in layout.edges) {
        if (edge.a.term == selected.term) focusTerms.add(edge.b.term);
        if (edge.b.term == selected.term) focusTerms.add(edge.a.term);
      }
    }

    final maxEdgeWeight = layout.edges.fold<double>(
      0,
      (maxWeight, edge) => math.max(maxWeight, edge.edge.weight),
    );

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // 弱边先画，强边压在上面。
    for (final edge in layout.edges.reversed) {
      final incident =
          selected == null ||
          edge.a.term == selected.term ||
          edge.b.term == selected.term;
      final normalized = maxEdgeWeight > 0
          ? edge.edge.weight / maxEdgeWeight
          : 0.0;
      final active = selected == null || incident;
      edgePaint
        ..color = incident && selected != null
            ? secondary.withValues(alpha: 0.30 + 0.30 * normalized)
            : onSurface.withValues(
                alpha: active ? 0.10 + 0.35 * normalized : 0.035,
              )
        ..strokeWidth = active ? 0.8 + 2.4 * normalized : 0.7;
      canvas.drawLine(
        Offset(edge.a.x, edge.a.y),
        Offset(edge.b.x, edge.b.y),
        edgePaint,
      );
    }

    final nodePaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()..style = PaintingStyle.stroke;
    final sortedNodes = List<TasteGraphNode>.from(layout.nodes)
      ..sort((a, b) => a.weight.compareTo(b.weight));
    for (final node in sortedNodes) {
      final isSelected = node.term == selected?.term;
      final focused = selected == null || focusTerms.contains(node.term);
      final weight = node.weight.clamp(0.0, 1.0).toDouble();
      final base = isSelected
          ? secondary
          : (node.degree > 0 ? primary : outline);
      final alpha = focused ? 1.0 : 0.18;
      final center = Offset(node.x, node.y);

      if (isSelected) {
        canvas.drawCircle(
          center,
          node.radius + 6,
          Paint()..color = secondary.withValues(alpha: 0.16),
        );
      }
      nodePaint.color = base.withValues(alpha: (0.22 + 0.62 * weight) * alpha);
      canvas.drawCircle(center, node.radius, nodePaint);
      borderPaint
        ..color = (isSelected ? onSurface : base).withValues(
          alpha: (isSelected ? 0.78 : 0.45) * alpha,
        )
        ..strokeWidth = isSelected ? 1.8 : 1.0;
      canvas.drawCircle(center, node.radius, borderPaint);
    }

    _paintLabels(canvas, size, selected, focusTerms);
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    TasteGraphNode? selected,
    Set<String> focusTerms,
  ) {
    final maxLabels = selected != null
        ? math.min(8, focusTerms.length + 1)
        : (size.width < 420 ? 12 : (size.width < 720 ? 18 : 24));
    final candidates = List<TasteGraphNode>.from(layout.nodes)
      ..sort((a, b) {
        int rank(TasteGraphNode node) {
          if (node.term == selected?.term) return 2;
          if (selected != null && focusTerms.contains(node.term)) return 1;
          return 0;
        }

        final byRank = rank(b).compareTo(rank(a));
        if (byRank != 0) return byRank;
        final byWeight = b.weight.compareTo(a.weight);
        return byWeight != 0 ? byWeight : a.term.compareTo(b.term);
      });

    final placed = <Rect>[];
    final occupied = <Rect>[
      for (final node in layout.nodes)
        Rect.fromCircle(
          center: Offset(node.x, node.y),
          radius: node.radius + 1.5,
        ),
    ];
    var drawn = 0;
    for (final node in candidates) {
      if (drawn >= maxLabels) break;
      if (selected != null && !focusTerms.contains(node.term)) continue;

      final isSelected = node.term == selected?.term;
      final weight = node.weight.clamp(0.0, 1.0).toDouble();
      final style = TextStyle(
        color: isSelected
            ? secondary
            : (focusTerms.contains(node.term) ? onSurface : onSurfaceVariant),
        fontFamily: fontFamily,
        fontSize: 11.0 + 1.5 * weight,
        fontWeight: isSelected
            ? FontWeight.w700
            : (weight > 0.6 ? FontWeight.w600 : FontWeight.w400),
        height: 1.1,
      );
      final text = TextPainter(
        text: TextSpan(text: node.term, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 104);
      final labelSize = Size(text.width, text.height);
      final gap = node.radius + 5;
      final candidatesRects = <Rect>[
        Rect.fromLTWH(
          node.x + gap,
          node.y - labelSize.height / 2,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          node.x - gap - labelSize.width,
          node.y - labelSize.height / 2,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          node.x - labelSize.width / 2,
          node.y + gap,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          node.x - labelSize.width / 2,
          node.y - gap - labelSize.height,
          labelSize.width,
          labelSize.height,
        ),
      ];

      Rect? chosen;
      for (final rect in candidatesRects) {
        final clamped = _clampRect(rect, size, 2);
        final fitsLabels = placed.every(
          (other) => !other.overlaps(clamped.inflate(2)),
        );
        final fitsNodes = occupied.every(
          (other) => !other.overlaps(clamped.inflate(1)),
        );
        if (fitsLabels && fitsNodes) {
          chosen = clamped;
          break;
        }
      }
      if (chosen == null && isSelected) {
        chosen = _clampRect(candidatesRects.first, size, 2);
      }
      if (chosen == null) continue;

      placed.add(chosen);
      drawn++;
      canvas.drawRRect(
        RRect.fromRectAndRadius(chosen.inflate(2), const Radius.circular(4)),
        Paint()..color = surface.withValues(alpha: isSelected ? 0.92 : 0.78),
      );
      text.paint(canvas, Offset(chosen.left, chosen.top));
    }
  }

  Rect _clampRect(Rect rect, Size size, double margin) {
    var dx = 0.0;
    if (rect.left < margin) dx = margin - rect.left;
    if (rect.right > size.width - margin) {
      dx = size.width - margin - rect.right;
    }
    var dy = 0.0;
    if (rect.top < margin) dy = margin - rect.top;
    if (rect.bottom > size.height - margin) {
      dy = size.height - margin - rect.bottom;
    }
    return rect.shift(Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _TasteGraphPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.selectedTerm != selectedTerm ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.onSurface != onSurface ||
      oldDelegate.onSurfaceVariant != onSurfaceVariant ||
      oldDelegate.surface != surface ||
      oldDelegate.outline != outline ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.textScaler != textScaler;
}
