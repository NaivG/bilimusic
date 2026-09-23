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
/// - **竖屏加宽 + 顶部专用滚动条**（见 [_EqMetrics.minBandSpacing]）：
///   竖屏端把内容撑到 ~573dp，多出来的部分只靠顶部那条专用滚动条横向
///   滚动。曲线区域恢复**按下即抓最近**。
/// - 拖动过程中回调 [onBandChanged]（调用方用本地草稿承接，不落盘），
///   松手 / 双击复位时回调 [onDragEnd] 提交。
/// - 节点与刻度的绘制尺寸按设备分档（见 [_EqMetrics]）。
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

/// 节点与刻度的尺寸档。
///
/// 抓取本身不是问题——整个曲面都是手势区，按下取最近频段，且按下偏移被
/// `_grab*` 吸收——问题在**看**与**滚**：竖屏手机上圆点又小、又被指尖
/// 整个遮住，8 个点还挤在 ~300dp 里（相邻只隔 ~27dp），中间几个点按不准。
/// 所以触屏档放大绘制尺寸，并给一个最小间距（见 [minBandSpacing]）把
/// 内容撑宽；多出来的部分只靠 [topPad] 高的顶部专用滚动条横向滚动，
/// 曲线区按下即抓，两条语义不重叠。
///
/// 分档键取 `shortestSide` 而不是 `width`：它是**设备**档位、旋转不变。
/// 横屏手机 `width` 会跳到 800+ 误入指针档，可那时 plot 虽然更宽，手指
/// 尺寸没变，小圆点照样难找。600dp 这条界与 `ResponsiveHelper` 的
/// 手机档、`app_shell` 的形态分界一致。
enum _EqMetrics {
  /// 触屏档：手机（含横屏）。
  touch(
    nodeRadius: 7,
    activeRadius: 11,
    nodeStroke: 2.2,
    labelSize: 11.5,
    labelGap: 34,
    minBandSpacing: 52,
    topPad: 16,
    barY: 8,
    barH: 6,
  ),

  /// 指针档：平板 / 桌面，鼠标精度下维持原尺寸。
  ///
  /// [minBandSpacing] = 0 → 不强制加宽：内容恒等于视口宽度，永远不滚，
  /// 顶部滚动条（[topPad] 点击带）也就永远不会激活，桌面交互与从前
  /// 逐条一致。
  pointer(
    nodeRadius: 4,
    activeRadius: 6,
    nodeStroke: 1.6,
    labelSize: 10,
    labelGap: 30,
    minBandSpacing: 0,
    topPad: 10,
    barY: 6,
    barH: 4,
  );

  const _EqMetrics({
    required this.nodeRadius,
    required this.activeRadius,
    required this.nodeStroke,
    required this.labelSize,
    required this.labelGap,
    required this.minBandSpacing,
    required this.topPad,
    required this.barY,
    required this.barH,
  });

  /// 空闲节点半径。
  final double nodeRadius;

  /// 拖动中（高亮）节点半径。
  final double activeRadius;

  /// 空闲节点描边宽度。
  final double nodeStroke;

  /// 频率 / dB 刻度字号。
  final double labelSize;

  /// 相邻频率标签的最小水平间距：略大于 [labelSize] 时一条标签的宽度，
  /// 窄 plot 上宁可跳过一条也不要叠字。激活项强制显示，离它不足此间距的
  /// 邻居让位（见绘制处的 `crowded`）。
  final double labelGap;

  /// 触屏档下相邻频点的**最小绘制间距**（dp）；0 = 不强制加宽。
  ///
  /// 内容宽度 = `minBandSpacing / Δt(默认频点里最紧的一对)` + 左右留白。
  /// 竖屏 360dp 手机下得到 ~573dp 的内容，其中 ~269dp 要滚才能看到。
  /// 它只决定抓取精度（点距越大越好按）——横向滚动已经收敛到顶部专用
  /// 滚动条，不再靠列间留白当横滑入口，这个数也就不用再在「留白可按」
  /// 与「热区可抓」之间打摆。
  final double minBandSpacing;

  /// 顶部滚动条点击带的高度（dp），同时是绘图区的上边距
  /// （plot.top = topPad）。内容比视口宽时，按进这一带是拖滚动条，
  /// 按在绘图区是抓频段；内容塞得下（不滚）时这一带照常抓频段。
  final double topPad;

  /// 滚动条滑块的绘制 y 与厚度（dp），画在 [topPad] 点击带内。
  final double barY;
  final double barH;

  static _EqMetrics of(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < 600 ? touch : pointer;
}

// ── 几何常量：State（布局 / 命中）与 Painter（绘制）共用一份 ──────────
// 上边距不再用常量：它随尺寸档走（[_EqMetrics.topPad]，触屏档要给滚动
// 条让出更高的点击带）。
const double _eqHeight = 236;
const double _eqLeftPad = 6;
const double _eqRightGutter = 30;
const double _eqBottomGutter = 18;

/// 默认频点里最紧的一对在对数轴上的间距（64 ↔ 125 Hz）。
///
/// 取自**默认**频点而不是当前频点：频点能被拖到只剩
/// [EqualizerBandModel.minFrequencyRatio]，按当前间距算宽度会边拖边变、
/// 还能把内容撑到 1000dp 以上。
final double _minDefaultDeltaT = () {
  final lo = math.log(EqualizerBandModel.minFrequency);
  final span = math.log(EqualizerBandModel.maxFrequency) - lo;
  var min = double.infinity;
  for (var i = 0; i < EqualizerBandModel.bandCount - 1; i++) {
    final a = math.log(EqualizerBandModel.defaultFrequencies[i]);
    final b = math.log(EqualizerBandModel.defaultFrequencies[i + 1]);
    min = math.min(min, (b - a) / span);
  }
  return min;
}();

/// 内容宽度：塞得下就是视口宽度（不滚），塞不下就按最小间距撑开。
double _contentWidthFor(_EqMetrics metrics, double viewportW) {
  if (metrics.minBandSpacing <= 0) return viewportW;
  final plotW = metrics.minBandSpacing / _minDefaultDeltaT;
  return math.max(viewportW, plotW + _eqLeftPad + _eqRightGutter);
}

class _EqualizerCurveState extends State<EqualizerCurve>
    with SingleTickerProviderStateMixin {
  /// 正在被拖拽 / 高亮的频段。
  int? _active;

  /// 抓取偏移：拖动开始时指针与节点之间的距离（对数频率域 / dB 域）。
  /// 拖动按**增量**解释而不是把节点瞬移到指针处，避免一上手就跳变。
  double? _grabFreqT;
  double? _grabGainDb;

  // ── 顶部专用滚动条（只有内容比视口宽时才激活）──────────────────────
  /// 滚动位置（dp，内容坐标系相对视口的左移量）。
  double _scrollPx = 0;

  /// 当前手势是不是「拖滚动条」（否则是拖频点）。
  bool _scrolling = false;

  /// **按下那一刻**的视口坐标。滚动条用它判定按在滑块上还是轨道上
  /// （轨道 = 先跳转再拖），不用 pan-start 的位置：`onPanStart` 要等
  /// 越过 touch slop（~18dp）才触发，带的还是越界那一刻的坐标——往哪边
  /// 拖就偏哪边。意图在 down 就定死。
  double _downDx = 0;
  double _downDy = 0;

  /// 滚动条拖动的锚点：pan-start 时的视口 x 与当时的滚动位置，按
  /// **绝对位移**解释，不累加每帧 delta（累加会漂）。锚在 pan-start 而
  /// 不是 down，是让 slop 那段位移不计入滚动——原生 Scrollable 也吞掉
  /// 它，内容不会在起手时平白跳 18dp。
  double _scrollAnchorDx = 0;
  double _scrollAnchorPx = 0;

  late final AnimationController _fling;

  // 以下四项由 [build] 每次写入，手势回调直接读——手势只会发生在 build
  // 之后。声明成 `late` 是为了让「读到未初始化」直接炸，而不是静默用 0。
  late _EqMetrics _metrics;
  late Size _contentSize;
  late double _maxScroll;

  /// 可见绘图区的右缘（视口坐标）：右侧钉死的 dB 刻度槽不算在内，
  /// [_followScroll] 用它决定把视口推多远。
  late double _clipRight;

  // 滚动条几何由 [_layoutBar] 在 build 时算好，手势与绘制共用同一份：
  // 「按在滑块上还是轨道上」的判定、拖动换算必须和画出来的滑块严格一致。
  late double _trackW;
  late double _thumbW;

  /// 手指每移动 1dp，内容滚多少 dp（= scrollMax / 滑块可行程）。
  late double _barScale;

  @override
  void initState() {
    super.initState();
    _fling = AnimationController(vsync: this)..addListener(_onFlingTick);
  }

  @override
  void dispose() {
    _fling.dispose();
    super.dispose();
  }

  void _onFlingTick() {
    final v = _fling.value.clamp(0.0, _maxScroll);
    if (v != _scrollPx) setState(() => _scrollPx = v);
  }

  /// 松手后的惯性。入参是**滚动方向上的内容速度**，调用方负责把手指速度
  /// 换算过去：曲面横滑是「内容跟手」（手指右甩 → 内容右移 → 滚动变小），
  /// 滚动条是「滑块跟手」（手指右甩 → 滚动变大），两者符号相反。
  void _startFling(double fingerVelocity) {
    if (_maxScroll <= 0 || !fingerVelocity.isFinite) return;
    if (fingerVelocity.abs() < 240) return;
    final raw = _scrollPx - fingerVelocity * 0.18;
    if (!raw.isFinite) return;
    final target = raw.clamp(0.0, _maxScroll);
    final dist = (target - _scrollPx).abs();
    if (dist < 1) return;
    final ms = (dist / fingerVelocity.abs() * 1000).clamp(100.0, 320.0).round();
    _fling.value = _scrollPx;
    _fling.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.decelerate,
    );
  }

  /// 由 [build] 算好滚动条几何：轨道宽、滑块宽与拖动换算比例。
  ///
  /// 滑块宽与 painter 的画法必须同源——「按在滑块上还是轨道上」的判定、
  /// 轨道跳转的换算，全都依赖这份几何，两边各算各的就会脱节。
  void _layoutBar(double viewportW, double maxScroll) {
    _trackW = math.max(0.0, viewportW - _eqRightGutter);
    if (maxScroll <= 0 || _trackW < 16) {
      // 不滚，或视口窄到放不下一条可用的滚动条（极端场景）：滑块退化、
      // 换算比例归零，滚动条点击带自然失效（曲线区照常抓频段）。
      _thumbW = _trackW;
      _barScale = 0;
      return;
    }
    final contentW = viewportW + maxScroll;
    _thumbW = (_trackW * viewportW / contentW).clamp(16.0, _trackW);
    final travel = _trackW - _thumbW;
    _barScale = travel > 0 ? maxScroll / travel : 0;
  }

  /// 轨道跳转：让滑块**中心**对齐到视口 x [viewX] 时的滚动位置。
  double _scrollForThumbCenterAt(double viewX) {
    final travel = _trackW - _thumbW;
    if (travel <= 0) return 0;
    final thumbLeft = (viewX - _thumbW / 2).clamp(0.0, travel);
    return thumbLeft / travel * _maxScroll;
  }

  Rect _plot(Size s) => Rect.fromLTRB(
    _eqLeftPad,
    _metrics.topPad,
    s.width - _eqRightGutter,
    s.height - _eqBottomGutter,
  );

  double _tOfFreq(double f) =>
      ((math.log(f) - _logMin) / (_logMax - _logMin)).clamp(0.0, 1.0);

  double _freqOfT(double t) =>
      math.exp(_logMin + t.clamp(0.0, 1.0) * (_logMax - _logMin));

  /// 对数频率 t → 内容坐标 x（与 Painter 的同名计算必须一致）。
  double _xOfFreqT(double t, Rect plot) => plot.left + t * plot.width;

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

  /// 拖动中让视口跟着节点走：节点被拖到视口边上时推开视口，
  /// 不然它会被右侧刻度槽 /左边缘整个吃掉，拖着拖着就看不见了。
  ///
  /// 只在滚得动时生效；节点频率本身**不**做视口钳制——否则滚到头之后
  /// 频点会被悄悄按在 `clipRight - 余量` 上，再也拖不到 20 kHz。
  double _followScroll(int band, double freq, Rect plot, double scroll) {
    if (_maxScroll <= 0) return scroll;
    final pad = _metrics.activeRadius + 3;
    final viewX = _xOfFreqT(_tOfFreq(freq), plot) - scroll;
    if (viewX > _clipRight - pad) {
      return (scroll + viewX - (_clipRight - pad)).clamp(0.0, _maxScroll);
    }
    if (viewX < pad) {
      return (scroll + viewX - pad).clamp(0.0, _maxScroll);
    }
    return scroll;
  }

  void _onPanStart(DragStartDetails d) {
    // 意图在 **down 那一刻**就定死（见 [_downDx]），不能用 d.localPosition
    // 判区域——那是过了 touch slop 才报出来的坐标，已经偏了。
    final inBar = _maxScroll > 0 && _downDy < _metrics.topPad;
    if (inBar) {
      setState(() {
        _scrolling = true;
        _active = null;
        _grabFreqT = null;
        _grabGainDb = null;
        // 按在滑块上 → 原地相对拖动；按在轨道上（滑块之外）→ 先把滑块
        // 中心跳到按下处（Material 滚动条语义），再从那里相对拖动。
        final thumbLeft = (_scrollPx / _maxScroll) * (_trackW - _thumbW);
        final onThumb = _downDx >= thumbLeft && _downDx <= thumbLeft + _thumbW;
        if (!onThumb) {
          _scrollPx = _scrollForThumbCenterAt(_downDx).clamp(0.0, _maxScroll);
        }
        _scrollAnchorDx = d.localPosition.dx;
        _scrollAnchorPx = _scrollPx;
      });
      return;
    }

    // 曲线区按下即抓最近频段——横向滚动已收敛到顶部滚动条，曲面上不再
    // 有「抓取 / 横滑」的二义性。
    final plot = _plot(_contentSize);
    final downDx = _downDx + _scrollPx;
    final i = _nearestBand(Offset(downDx, d.localPosition.dy), plot);

    // 抓取偏移从 pan-start 的位置起算，节点在起手那一刻原地不动：
    // 若锚到 down，越 slop 的那 ~18dp 会一次性灌进频率，节点先跳一下。
    final startDx = d.localPosition.dx + _scrollPx;
    setState(() {
      _scrolling = false;
      _active = i;
      _grabFreqT =
          _tOfLocal(startDx, plot) - _tOfFreq(widget.model.frequencies[i]);
      _grabGainDb = _dbOfY(d.localPosition.dy, plot) - widget.model.gainsDb[i];
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_scrolling) {
      // 滑块跟手：手指位移 × 换算比例（内容比滑块行程长，滚得比手指快）。
      final target =
          _scrollAnchorPx + (d.localPosition.dx - _scrollAnchorDx) * _barScale;
      final v = target.clamp(0.0, _maxScroll);
      if (v != _scrollPx) setState(() => _scrollPx = v);
      return;
    }

    final i = _active;
    final grabT = _grabFreqT;
    final grabDb = _grabGainDb;
    if (i == null || grabT == null || grabDb == null) return;

    final plot = _plot(_contentSize);
    final contentDx = d.localPosition.dx + _scrollPx;
    final nodeT = (_tOfLocal(contentDx, plot) - grabT).clamp(0.0, 1.0);
    // 先按该频段自己的切分区间收敛，再拿去推节点位置——不然频点被模型
    // 钉在区间边界时，视口会跟着一个「已经不动了」的 t 一直漂。
    final (low, high) = widget.model.frequencyRange(i);
    final freq = _freqOfT(nodeT).clamp(low, high);

    final scroll = _followScroll(i, freq, plot, _scrollPx);
    if (scroll != _scrollPx) setState(() => _scrollPx = scroll);

    widget.onBandChanged(
      i,
      frequency: freq,
      gainDb: _dbOfY(d.localPosition.dy, plot) - grabDb,
    );
  }

  void _onPanEnd(DragEndDetails d) {
    if (_scrolling) {
      _scrolling = false;
      // 滚动条的语义是「滑块跟手」（手指右甩 → 内容左移 → 变大），与
      // 曲面横滑的「内容跟手」方向相反，所以速度取负号再按换算比例放大：
      // 滑块甩多快，内容就该滚多快。
      _startFling(-d.velocity.pixelsPerSecond.dx * _barScale);
      return;
    }
    _clearActive();
    widget.onDragEnd();
  }

  void _onPanCancel() {
    _scrolling = false;
    _clearActive();
  }

  void _onDoubleTapDown(TapDownDetails d) {
    // 滚动条区域不参与复位——那一下想操作的是滚动，不是想把频段归零。
    if (_maxScroll > 0 && d.localPosition.dy < _metrics.topPad) return;
    final plot = _plot(_contentSize);
    final contentDx = d.localPosition.dx + _scrollPx;
    final i = _nearestBand(Offset(contentDx, d.localPosition.dy), plot);
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

  static final double _logMin = math.log(EqualizerBandModel.minFrequency);
  static final double _logMax = math.log(EqualizerBandModel.maxFrequency);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.enabled
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.35);
    final metrics = _EqMetrics.of(context);
    return SizedBox(
      height: _eqHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, c) {
          final viewportW = c.maxWidth;
          final contentW = _contentWidthFor(metrics, viewportW);
          final maxScroll = math.max(0.0, contentW - viewportW);
          // 视口变宽（旋转 / 拉大窗口）后把滚动位置收回来。这里**不** setState：
          // 本次 build 的绘制与之后的手势都会读到收敛后的值。
          final scroll = _scrollPx.clamp(0.0, maxScroll);
          _metrics = metrics;
          _contentSize = Size(contentW, _eqHeight);
          _maxScroll = maxScroll;
          _layoutBar(viewportW, maxScroll);
          _clipRight = viewportW - _eqRightGutter;
          if (scroll != _scrollPx) _scrollPx = scroll;

          final contentSize = _contentSize;
          return Listener(
            // 惯性还在跑时按下即刹停，否则点一下图表它还要继续滑半秒。
            // 顺手记下 down 的坐标：这是唯一能拿到「用户按在哪儿」的时机
            // （见 [_downDx]），`onPanStart` 来的时候已经过了 slop。
            onPointerDown: (e) {
              _fling.stop();
              _downDx = e.localPosition.dx;
              _downDy = e.localPosition.dy;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: _onPanCancel,
              onDoubleTapDown: _onDoubleTapDown,
              child: CustomPaint(
                size: Size(viewportW, _eqHeight),
                painter: _EqCurvePainter(
                  model: widget.model,
                  active: _active,
                  accent: accent,
                  plot: _plot(contentSize),
                  metrics: metrics,
                  scrollX: _scrollPx,
                  scrollMax: maxScroll,
                  thumbWidth: _thumbW,
                  barActive: _scrolling,
                  gridColor: scheme.onSurface.withValues(alpha: 0.10),
                  zeroColor: scheme.onSurface.withValues(alpha: 0.22),
                  bandColor: scheme.onSurfaceVariant.withValues(alpha: 0.30),
                  labelColor: scheme.onSurfaceVariant,
                ),
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

  /// 尺寸档（节点 / 字号 / 滚动条几何）。
  final _EqMetrics metrics;

  /// 横向滚动位置：内容整体左移这么多，坐标系不变。
  final double scrollX;

  /// 最大可滚距离；0 = 内容塞得下视口，不画滚动条。
  final double scrollMax;

  /// 滚动条滑块宽度：State 的 `_thumbW`，同一份几何（[_EqualizerCurveState._layoutBar]），
  /// 拖动换算才不会和画面脱节。
  final double thumbWidth;

  /// 滚动条拖动中：滑块用 accent 高亮，给「正在滚」的即时反馈。
  final bool barActive;

  _EqCurvePainter({
    required this.model,
    required this.active,
    required this.accent,
    required this.gridColor,
    required this.zeroColor,
    required this.bandColor,
    required this.labelColor,
    required this.plot,
    required this.metrics,
    required this.scrollX,
    required this.scrollMax,
    required this.thumbWidth,
    required this.barActive,
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

    // 顶部专用滚动条：画在最底层。它是竖屏横向滚动的唯一入口，
    // 点击带（topPad）由 State 的手势处理，几何与 State 共用一份。
    _drawScrollbar(canvas, size);

    // 绘图区 = 视口扣掉右侧钉住的 dB 刻度槽；内容整体按 scrollX 平移。
    final clip = Rect.fromLTRB(0, 0, size.width - _eqRightGutter, size.height);
    if (clip.width <= 0) return;
    canvas.save();
    canvas.clipRect(clip);
    canvas.translate(-scrollX, 0);

    // ── 横向 dB 网格（刻度文字稍后钉在视口右侧画）────────────────
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
    final act = active;
    // 激活项的标签是**强制显示**的（它下面就是要读的读数），所以先拿到它的
    // x，让离它太近的邻居让位——否则加大字号后激活标签会压到邻居身上。
    // 被 `crowded` 挡掉的和没达到 [labelGap] 的都不画，剩下任意两条已画标签
    // 之间都 ≥ labelGap（含激活项）。
    final activeX = act == null ? null : _xOfFreq(model.frequencies[act]);
    var lastLabelX = -100.0;
    for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
      final p = Offset(
        _xOfFreq(model.frequencies[i]),
        _yOfDb(model.gainsDb[i].clamp(-_maxDb, _maxDb).toDouble()),
      );
      final isActive = i == act;
      if (isActive) {
        // 拖动中指尖会盖住节点，所以高亮半径放大到指尖之外还露得出一圈。
        canvas.drawCircle(p, metrics.activeRadius, Paint()..color = accent);
      } else {
        canvas.drawCircle(
          p,
          metrics.nodeRadius,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = metrics.nodeStroke
            ..isAntiAlias = true,
        );
      }

      // 频率标签：相邻太挤时跳过非激活项，避免互相叠字。
      final freq = model.frequencies[i];
      final text = freq < 1000
          ? '${freq.round()}'
          : '${(freq / 1000).toStringAsFixed(freq < 10000 ? 1 : 0)}k';
      final x = p.dx;
      final crowded =
          activeX != null &&
          !isActive &&
          (x - activeX).abs() < metrics.labelGap;
      if (isActive || (!crowded && x - lastLabelX >= metrics.labelGap)) {
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

    // 回到视口坐标系，画不随内容滚动的东西。
    canvas.restore();

    // ── 钉在右侧的 dB 刻度：它标注的是「这一行是多少 dB」，与横向
    //    滚到哪儿无关，跟着内容跑掉就没人知道网格线是什么意思了。──
    for (final db in _gridDb) {
      final y = _yOfDb(db);
      _label(
        canvas,
        db == 0 ? '0' : '${db > 0 ? '+' : ''}${db.toInt()}',
        Offset(clip.right + 6, y - 6),
        labelColor,
      );
    }
  }

  /// 顶部专用滚动条（内容比视口宽时才画）：轨道 + 滑块。
  ///
  /// 几何（滑块宽度）来自 State 的 [_EqualizerCurveState._layoutBar]，
  /// 位置 / 厚度随尺寸档走（[_EqMetrics.barY] / [barH]）。
  void _drawScrollbar(Canvas canvas, Size size) {
    if (scrollMax <= 0) return;
    final w = size.width - _eqRightGutter;
    if (w <= 8) return;
    final y = metrics.barY;
    final h = metrics.barH;
    final radius = Radius.circular(h / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, y, w, h), radius),
      Paint()..color = labelColor.withValues(alpha: 0.10),
    );
    final x = (scrollX / scrollMax).clamp(0.0, 1.0) * (w - thumbWidth);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, thumbWidth, h), radius),
      Paint()
        ..color = barActive
            ? accent.withValues(alpha: 0.9)
            : labelColor.withValues(alpha: 0.38),
    );
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
        style: TextStyle(fontSize: metrics.labelSize, color: color),
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
      old.metrics != metrics ||
      old.scrollX != scrollX ||
      old.scrollMax != scrollMax ||
      old.thumbWidth != thumbWidth ||
      old.barActive != barActive ||
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
