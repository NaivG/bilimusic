import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/player/logic/compressor_settings.dart';

/// 压缩器**传递曲线**（dB-in → dB-out）的可视化。
///
/// 这是个「通用」曲线图，与具体压缩器实现无关：
/// - x 轴 = 输入 dBFS，y 轴 = 输出 dBFS；
/// - 一条无涂层 [0 dBFS, _dbFloor] 的对角线是**无压缩参考**（unity）；
/// - 阈值以下曲线与 unity 重合；
/// - 阈值以上曲线按 ratio 折叠向下；threshold 处有竖直标线，
///   标线右侧整块加淡色 wash 提示「这里是压缩区」；
/// - 拐点两侧的 [kneeDb/2] 区间内做二次曲线软拐，曲线自然过渡；
/// - unity 与压缩曲线围成的楔形用淡色填充 = 该参数下"压了多少 dB" 的直观读数。
///
/// 风格与 [EqualizerCurve] 同构（细网格 + 单一 accent 色 + 标尺在右/下边），
/// 复用同一套主题颜色。无 PCM tap、无动画——曲线形状由 5 个参数决定，
/// 滑块拖动期间通过本地草稿刷新重绘。
class CompressorCurve extends StatelessWidget {
  final double threshold; // linear amplitude (lavfi)
  final double ratio;
  final double makeup; // linear amplitude
  final bool enabled;

  /// 软拐宽度因子（lavfi `knee`），默认走 mpv_audio_kit 默认。
  /// UI 不暴露，按需通过外部传入可调（当前项目固定）。
  final double knee;

  const CompressorCurve({
    super.key,
    required this.threshold,
    required this.ratio,
    required this.makeup,
    required this.enabled,
    this.knee = mpv.AcompressorSettings.kneeDefault,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = enabled
        ? (isDark ? Colors.white : scheme.primary)
        : scheme.onSurface.withValues(alpha: 0.35);

    return SizedBox(
      height: 168,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _KneePainter(
            thresholdDb: CompressorSettingsModel.amplitudeToDb(threshold),
            ratio: ratio,
            kneeDb: CompressorSettingsModel.amplitudeToDb(
              knee.clamp(
                mpv.AcompressorSettings.kneeMin,
                mpv.AcompressorSettings.kneeMax,
              ),
            ),
            makeupDb: CompressorSettingsModel.amplitudeToDb(makeup),
            enabled: enabled,
            accent: accent,
            gridColor: scheme.onSurface.withValues(alpha: 0.10),
            axisColor: scheme.onSurface.withValues(alpha: 0.45),
            axisDim: scheme.onSurface.withValues(alpha: 0.22),
            washColor: accent.withValues(alpha: 0.06),
            labelColor: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 软拐压缩器传递曲线计算（dB-in → dB-out，RBJ-cookbook 风格）。
///
/// 阈值以下 unity；跨越 knee 时二次曲线软拐；拐点之上按 1/ratio 折叠；
/// 最后整体加 makeup。三段式与 ffmpeg `af_acompressor` 的实现同源，
/// 但去掉了 attack/release 的时间轴（这是个**稳态曲线**，与时间常数无关）。
double _compressorKneeDb(
  double inputDb, {
  required double thresholdDb,
  required double ratio,
  required double kneeDb,
  required double makeupDb,
}) {
  final diff = inputDb - thresholdDb;
  double out;
  if (kneeDb > 0 && (2 * diff).abs() <= kneeDb) {
    final factor = (1.0 / ratio - 1.0) / (2.0 * kneeDb);
    out = inputDb + factor * math.pow(diff + kneeDb / 2, 2).toDouble();
  } else if (diff > kneeDb / 2) {
    out = thresholdDb + diff / ratio;
  } else {
    out = inputDb;
  }
  return out + makeupDb;
}

const double _dbFloor = -60;
const double _dbCeil = 0;

class _KneePainter extends CustomPainter {
  final double thresholdDb;
  final double ratio;
  final double kneeDb;
  final double makeupDb;
  final bool enabled;
  final Color accent;
  final Color gridColor;
  final Color axisColor;
  final Color axisDim;
  final Color washColor;
  final Color labelColor;

  _KneePainter({
    required this.thresholdDb,
    required this.ratio,
    required this.kneeDb,
    required this.makeupDb,
    required this.enabled,
    required this.accent,
    required this.gridColor,
    required this.axisColor,
    required this.axisDim,
    required this.washColor,
    required this.labelColor,
  });

  static const double _rightGutter = 24;
  static const double _bottomGutter = 16;
  static const _grid = [-48.0, -36.0, -24.0, -12.0];

  double _kneeOut(double inDb) => _compressorKneeDb(
    inDb,
    thresholdDb: thresholdDb,
    ratio: ratio,
    kneeDb: kneeDb,
    makeupDb: makeupDb,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      2,
      6,
      size.width - _rightGutter,
      size.height - _bottomGutter,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    double x(double db) =>
        plot.left + ((db - _dbFloor) / (_dbCeil - _dbFloor)) * plot.width;
    double y(double db) =>
        plot.top +
        (1 -
                ((db.clamp(_dbFloor, _dbCeil) - _dbFloor) /
                    (_dbCeil - _dbFloor))) *
            plot.height;

    // ── 网格 + 轴刻度 ────────────────────────────────────────────────
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final db in _grid) {
      canvas.drawLine(
        Offset(x(db), plot.top),
        Offset(x(db), plot.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(plot.left, y(db)),
        Offset(plot.right, y(db)),
        grid,
      );
      _label(
        canvas,
        db.toInt().toString(),
        Offset(x(db), plot.bottom + 3),
        labelColor,
        center: true,
      );
      _label(
        canvas,
        db.toInt().toString(),
        Offset(plot.right + 3, y(db) - 5),
        labelColor,
      );
    }

    // ── 无压缩参考（unity） ──────────────────────────────────────────
    canvas.drawLine(
      Offset(x(_dbFloor), y(_dbFloor)),
      Offset(x(_dbCeil), y(_dbCeil)),
      Paint()
        ..color = axisDim
        ..strokeWidth = 1,
    );

    // ── 阈值标线 + 右侧"压缩区" wash ────────────────────────────────
    final tx = x(thresholdDb.clamp(_dbFloor, _dbCeil));
    canvas.drawRect(
      Rect.fromLTRB(tx, plot.top, plot.right, plot.bottom),
      Paint()..color = washColor,
    );
    canvas.drawLine(
      Offset(tx, plot.top),
      Offset(tx, plot.bottom),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );

    // ── 压缩传递曲线 + 与 unity 围成的楔形（gain reduction 可视化） ──
    final curve = Path();
    final wedge = Path();
    const steps = 160;
    for (var i = 0; i <= steps; i++) {
      final inputDb = _dbFloor + (i / steps) * (_dbCeil - _dbFloor);
      final px = x(inputDb);
      final py = y(_kneeOut(inputDb));
      if (i == 0) {
        curve.moveTo(px, py);
        wedge.moveTo(px, y(inputDb));
      } else {
        curve.lineTo(px, py);
      }
    }
    for (var i = steps; i >= 0; i--) {
      final inputDb = _dbFloor + (i / steps) * (_dbCeil - _dbFloor);
      wedge.lineTo(x(inputDb), y(_kneeOut(inputDb)));
    }
    wedge.close();
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(wedge, Paint()..color = accent.withValues(alpha: 0.10));
    canvas.restore();
    canvas.drawPath(
      curve,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    // ── 阈值标点的 GR 文本：当前参数下"再多大信号会被压到几 dB" ──
    // 标在曲线末端（0 dBFS 输入）处，读数为「压完后输出的 dBFS」；
    // 与 unity 的差 = 此处被压掉的 dB 数，是 ratio/threshold 的直观读数。
    final grAt = _kneeOut(_dbCeil);
    final grAmount = _dbCeil - grAt;
    if (enabled && grAmount > 0.1) {
      _label(
        canvas,
        '−${grAmount.toStringAsFixed(1)} dB GR @0',
        Offset(plot.right - 6, plot.top + 2),
        accent,
        right: true,
      );
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool center = false,
    bool right = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (center) dx -= tp.width / 2;
    if (right) dx -= tp.width;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_KneePainter old) =>
      old.thresholdDb != thresholdDb ||
      old.ratio != ratio ||
      old.kneeDb != kneeDb ||
      old.makeupDb != makeupDb ||
      old.enabled != enabled ||
      old.accent != accent ||
      old.gridColor != gridColor ||
      old.axisColor != axisColor ||
      old.labelColor != labelColor;
}
