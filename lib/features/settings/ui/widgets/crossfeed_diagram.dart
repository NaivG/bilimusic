import 'package:flutter/material.dart';

/// 交叉回馈的**示意图**——两张通道源（L / R）到听者头部，
/// 直达同耳的连线恒亮，对侧串扰的弧线随 strength 增强而由淡变粗。
///
/// 这是一张"路由拓扑图"：
/// - 头部居中，两耳、两个声源分列两侧；
/// - 同耳直连始终存在（accent 色实线）；
/// - 跨耳弧线（L→右耳 / R→左耳）的**透明度 + 线宽**随 strength 同步
///   增长：0% 时几乎不可见，100% 时与直达线几乎等强；
/// - **弧高**随 range 增长：低架截频越高，串扰的频段越宽，对应图中
///   弧线越"高耸"地绕过听者头部（直观对应声场宽度）。
///
/// 这是**静态可视化**，用于把 strength / range 两个抽象参数映射到一目了然的路由变化。
class CrossfeedDiagram extends StatelessWidget {
  final double strength; // 0..1
  final double range; // 0..1
  final bool enabled;

  const CrossfeedDiagram({
    super.key,
    required this.strength,
    required this.range,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _CrossfeedPainter(
            strength: strength,
            range: range,
            enabled: enabled,
            accent: _accentOf(context),
            line: _lineOf(context),
            surface: _surfaceOf(context),
            label: _labelOf(context),
          ),
        ),
      ),
    );
  }

  static Color _accentOf(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final isDark = Theme.of(c).brightness == Brightness.dark;
    return isDark ? Colors.white : scheme.primary;
  }

  static Color _lineOf(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.30);

  static Color _surfaceOf(BuildContext c) =>
      Theme.of(c).colorScheme.surfaceContainerHighest;

  static Color _labelOf(BuildContext c) =>
      Theme.of(c).colorScheme.onSurfaceVariant;
}

class _CrossfeedPainter extends CustomPainter {
  final double strength;
  final double range;
  final bool enabled;
  final Color accent;
  final Color line;
  final Color surface;
  final Color label;

  _CrossfeedPainter({
    required this.strength,
    required this.range,
    required this.enabled,
    required this.accent,
    required this.line,
    required this.surface,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dimmed = enabled ? accent : accent.withValues(alpha: 0.35);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final span = (size.width * 0.34).clamp(60.0, 220.0);

    final lSrc = Offset(cx - span, cy);
    final rSrc = Offset(cx + span, cy);
    final headR = 20.0;
    final lEar = Offset(cx - headR, cy);
    final rEar = Offset(cx + headR, cy);

    // Listener head.
    canvas.drawCircle(
      Offset(cx, cy),
      headR,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Ears.
    for (final ear in [lEar, rEar]) {
      canvas.drawCircle(ear, 3, Paint()..color = label.withValues(alpha: 0.7));
    }

    // Direct same-ear paths — always full strength.
    final direct = Paint()
      ..color = dimmed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(lSrc, lEar, direct);
    canvas.drawLine(rSrc, rEar, direct);

    // Crossed paths — arc over (L→right ear) and under (R→left ear),
    // their presence scaling with strength.
    final crossPaint = Paint()
      ..color = dimmed.withValues(alpha: 0.2 + 0.8 * strength)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 + 2.5 * strength
      ..strokeCap = StrokeCap.round;
    final arch = headR + 16 + 18 * range; // taller arc → wider soundstage
    final over = Path()
      ..moveTo(lSrc.dx, lSrc.dy)
      ..quadraticBezierTo(cx, cy - arch, rEar.dx, rEar.dy);
    final under = Path()
      ..moveTo(rSrc.dx, rSrc.dy)
      ..quadraticBezierTo(cx, cy + arch, lEar.dx, lEar.dy);
    canvas.drawPath(over, crossPaint);
    canvas.drawPath(under, crossPaint);

    // Source nodes + L/R labels.
    void node(Offset at, String text) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: 22, height: 16),
          const Radius.circular(4),
        ),
        Paint()..color = surface,
      );
      _label(canvas, text, at, dimmed, center: true, middle: true);
    }

    node(lSrc, 'L');
    node(rSrc, 'R');

    // Bleed caption (strength 数值） — 让示意图自解释 strength 在做什么。
    _label(
      canvas,
      '串扰 ${(strength * 100).round()}%',
      Offset(cx, size.height - 12),
      enabled ? label.withValues(alpha: 0.85) : label.withValues(alpha: 0.45),
      fontSize: 10.5,
      center: true,
      middle: true,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool center = false,
    bool middle = false,
    double fontSize = 11,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    var dy = at.dy - tp.height / 2;
    if (center) dx -= tp.width / 2;
    if (!middle) dy -= tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_CrossfeedPainter old) =>
      old.strength != strength ||
      old.range != range ||
      old.enabled != enabled ||
      old.accent != accent ||
      old.line != line ||
      old.surface != surface ||
      old.label != label;
}
