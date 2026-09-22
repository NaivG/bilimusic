import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bilimusic/features/player/logic/equalizer_bands.dart';

/// 可视化 8 段可调频段均衡器：对数频率轴上的连续响应曲线。
///
/// - 每个频段是一个可拖拽节点：**横向拖 = 调中心频率（可调频段），
///   纵向拖 = 调增益**；频率越界由 [EqualizerBandModel.withBand]
///   收敛回该频段自己的切分区间，因此频段永远不会被拖到重叠。
/// - 淡色细线是各段自己的钟形响应（peaking 原型曲线，节点恰好落在
///   该段的中心增益上），粗线是 8 段级联后的合成响应（dB 域相加）。
///   频段按几何中点切分、在共享边界处衔接，合成曲线天然是平滑的
///   斜坡——不存在直上直下的台阶。
/// - 拖动过程中回调 [onBandChanged]（调用方用本地草稿承接，不落盘），
///   松手 / 双击复位时回调 [onDragEnd] 提交。
class EqualizerCurve extends StatefulWidget {
  final EqualizerBandModel model;

  /// 是否启用（只影响配色，不锁手势——允许先摆好曲线再打开开关）。
  final bool enabled;
  final void Function(int band, {double? frequency, double? gainDb})
  onBandChanged;
  final VoidCallback onDragEnd;

  const EqualizerCurve({
    super.key,
    required this.model,
    required this.enabled,
    required this.onBandChanged,
    required this.onDragEnd,
  });

  @override
  State<EqualizerCurve> createState() => _EqualizerCurveState();
}

class _EqualizerCurveState extends State<EqualizerCurve> {
  /// 正在被拖拽 / 高亮的频段。
  int? _active;

  /// 抓取偏移：拖动开始时指针与节点之间的距离（对数频率域 / dB 域）。
  /// 拖动按**增量**解释而不是把节点瞬移到指针处，避免一上手就跳变。
  double? _grabFreqT;
  double? _grabGainDb;

  static const double _height = 236;
  static const double _leftPad = 6;
  static const double _rightGutter = 30;
  static const double _bottomGutter = 18;
  static const double _topPad = 10;

  static final double _logMin = math.log(EqualizerBandModel.minFrequency);
  static final double _logMax = math.log(EqualizerBandModel.maxFrequency);

  Rect _plot(Size s) => Rect.fromLTRB(
    _leftPad,
    _topPad,
    s.width - _rightGutter,
    s.height - _bottomGutter,
  );

  double _tOfFreq(double f) =>
      ((math.log(f) - _logMin) / (_logMax - _logMin)).clamp(0.0, 1.0);

  double _freqOfT(double t) =>
      math.exp(_logMin + t.clamp(0.0, 1.0) * (_logMax - _logMin));

  double _dbOfY(double y, Rect plot) =>
      EqualizerBandModel.maxGainDb -
      ((y - plot.top) / plot.height) * 2 * EqualizerBandModel.maxGainDb;

  double _tOfLocal(double dx, Rect plot) =>
      ((dx - plot.left) / plot.width).clamp(0.0, 1.0);

  /// 按对数 x 找最近的频段。
  int _nearestBand(Offset local, Rect plot) {
    final t = _tOfLocal(local.dx, plot);
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
      final d = (t - _tOfFreq(widget.model.frequencies[i])).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _onPanStart(DragStartDetails d, Size size) {
    final plot = _plot(size);
    final i = _nearestBand(d.localPosition, plot);
    setState(() {
      _active = i;
      _grabFreqT =
          _tOfLocal(d.localPosition.dx, plot) -
          _tOfFreq(widget.model.frequencies[i]);
      _grabGainDb = _dbOfY(d.localPosition.dy, plot) - widget.model.gainsDb[i];
    });
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    final i = _active;
    final grabT = _grabFreqT;
    final grabDb = _grabGainDb;
    if (i == null || grabT == null || grabDb == null) return;
    final plot = _plot(size);
    widget.onBandChanged(
      i,
      frequency: _freqOfT(_tOfLocal(d.localPosition.dx, plot) - grabT),
      gainDb: _dbOfY(d.localPosition.dy, plot) - grabDb,
    );
  }

  void _onPanEnd(DragEndDetails d) {
    _clearActive();
    widget.onDragEnd();
  }

  void _onDoubleTapDown(TapDownDetails d, Size size) {
    final i = _nearestBand(d.localPosition, _plot(size));
    widget.onBandChanged(i, gainDb: 0);
    widget.onDragEnd();
  }

  void _clearActive() {
    if (_active == null && _grabFreqT == null && _grabGainDb == null) return;
    setState(() {
      _active = null;
      _grabFreqT = null;
      _grabGainDb = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.enabled
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.35);
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, _height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _onPanStart(d, size),
            onPanUpdate: (d) => _onPanUpdate(d, size),
            onPanEnd: _onPanEnd,
            onPanCancel: _clearActive,
            onDoubleTapDown: (d) => _onDoubleTapDown(d, size),
            child: CustomPaint(
              size: size,
              painter: _EqCurvePainter(
                model: widget.model,
                active: _active,
                accent: accent,
                plot: _plot(size),
                gridColor: scheme.onSurface.withValues(alpha: 0.10),
                zeroColor: scheme.onSurface.withValues(alpha: 0.22),
                bandColor: scheme.onSurfaceVariant.withValues(alpha: 0.30),
                labelColor: scheme.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final EqualizerBandModel model;
  final int? active;
  final Color accent;
  final Color gridColor;
  final Color zeroColor;
  final Color bandColor;
  final Color labelColor;
  final Rect plot;

  _EqCurvePainter({
    required this.model,
    required this.active,
    required this.accent,
    required this.gridColor,
    required this.zeroColor,
    required this.bandColor,
    required this.labelColor,
    required this.plot,
  });

  static const double _maxDb = EqualizerBandModel.maxGainDb;
  static const List<double> _gridDb = [12.0, 6.0, 0.0, -6.0, -12.0];

  static final double _logMin = math.log(EqualizerBandModel.minFrequency);
  static final double _logSpan =
      math.log(EqualizerBandModel.maxFrequency) - _logMin;

  double _yOfDb(double db) =>
      plot.top + (1 - (db + _maxDb) / (2 * _maxDb)) * plot.height;

  double _xOfT(double t) => plot.left + t.clamp(0.0, 1.0) * plot.width;

  double _xOfFreq(double f) => _xOfT((math.log(f) - _logMin) / _logSpan);

  @override
  void paint(Canvas canvas, Size size) {
    if (plot.width <= 0 || plot.height <= 0) return;

    // ── 横向 dB 网格 + 右侧刻度 ─────────────────────────────────
    for (final db in _gridDb) {
      final y = _yOfDb(db);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = db == 0 ? zeroColor : gridColor,
      );
      _label(
        canvas,
        db == 0 ? '0' : '${db > 0 ? '+' : ''}${db.toInt()}',
        Offset(plot.right + 6, y - 6),
        labelColor,
      );
    }

    // ── 频段切分边界（几何中点）：可视化「不重叠」的区间归属 ──
    for (var i = 0; i < EqualizerBandModel.bandCount - 1; i++) {
      final x = _xOfFreq(model.regionRight(i));
      _dashedLine(
        canvas,
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = gridColor,
      );
    }

    // 曲线主体都裁剪在绘图区内（合成响应可能超出 ±12 dB）。
    canvas.save();
    canvas.clipRect(plot.inflate(1));

    // ── 双极性填充：合成曲线与 0 dB 中线围成的面积 ──────────────
    // 合成曲线采样一次、路径复用给填充与描边（拖动时每帧都会重绘）。
    final combinedPath = _samplePath(model.combinedGainDbAt, 160);
    final zeroY = _yOfDb(0);
    final fill = Path.from(combinedPath)
      ..lineTo(plot.right, zeroY)
      ..lineTo(plot.left, zeroY)
      ..close();
    canvas.drawPath(fill, Paint()..color = accent.withValues(alpha: 0.12));

    // ── 各段自己的钟形响应（淡色细线） ──────────────────────────
    for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
      canvas.drawPath(
        _samplePath((f) => model.bandGainDbAt(i, f), 96),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = bandColor
          ..isAntiAlias = true,
      );
    }

    // ── 合成响应（粗线） ────────────────────────────────────────
    canvas.drawPath(
      combinedPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent
        ..isAntiAlias = true,
    );
    canvas.restore();

    // ── 节点 + 频率标签 ────────────────────────────────────────
    var lastLabelX = -100.0;
    for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
      final p = Offset(
        _xOfFreq(model.frequencies[i]),
        _yOfDb(model.gainsDb[i].clamp(-_maxDb, _maxDb).toDouble()),
      );
      final isActive = i == active;
      if (isActive) {
        canvas.drawCircle(p, 5.5, Paint()..color = accent);
      } else {
        canvas.drawCircle(
          p,
          3.2,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..isAntiAlias = true,
        );
      }

      // 频率标签：相邻太挤时跳过非激活项，避免互相叠字。
      final freq = model.frequencies[i];
      final text = freq < 1000
          ? '${freq.round()}'
          : '${(freq / 1000).toStringAsFixed(freq < 10000 ? 1 : 0)}k';
      final x = p.dx;
      if (isActive || x - lastLabelX >= 30) {
        _label(
          canvas,
          text,
          Offset(x, plot.bottom + 4),
          isActive ? accent : labelColor,
          center: true,
        );
        lastLabelX = x;
      }
    }
  }

  /// 在对数频率轴上均匀采样 [of] 连成折线路径（采样足够密，视觉连续）。
  Path _samplePath(double Function(double freq) of, int points) {
    final pts = _sample(of, points);
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  List<Offset> _sample(double Function(double freq) of, int points) {
    return [
      for (var i = 0; i < points; i++)
        () {
          final t = i / (points - 1);
          final freq = math.exp(_logMin + t * _logSpan);
          return Offset(
            _xOfT(t),
            _yOfDb(of(freq).clamp(-_maxDb - 3, _maxDb + 3).toDouble()),
          );
        }(),
    ];
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 3.0;
    const gap = 3.0;
    final dist = (b - a).distance;
    final dir = (b - a) / dist;
    var pos = 0.0;
    while (pos < dist) {
      final end = math.min(pos + dash, dist);
      canvas.drawLine(a + dir * pos, a + dir * end, paint);
      pos = end + gap;
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? Offset(at.dx - tp.width / 2, at.dy) : at);
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) =>
      old.active != active ||
      old.accent != accent ||
      old.plot != plot ||
      _listNe(old.model.frequencies, model.frequencies) ||
      _listNe(old.model.gainsDb, model.gainsDb);

  static bool _listNe(List<double> a, List<double> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
}
