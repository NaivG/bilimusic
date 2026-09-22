import 'dart:math' as math;

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

/// 8 段**可调频段**图形均衡器的纯逻辑模型（引擎侧对应 lavfi
/// `anequalizer`，每段是一个 peaking 钟形滤波器）。
///
/// 本类只负责几何与数学：频点、增益、带宽推导、响应曲线计算，
/// 以及与 [mpv.AnequalizerSettings] 的互转。不 import Flutter、
/// 不持有引擎状态——落盘与下发走 `effects_providers.dart` 的
/// 效果包链路（AudioEffects.anequalizer 槽位）。
///
/// ## 频段切分不变量（防重叠 + 平滑过渡的核心）
///
/// - 每个频段「拥有」自己与相邻频段之间的**几何中点**围成的开区间
///   `(L_i, R_i)`（首段左界取 20 Hz、末段右界取 20 kHz）。8 个区间
///   首尾相接恰好铺满整个可听域：`R_i == L_{i+1}`，既不重叠也无空隙；
/// - 频点可调范围被约束在 `f_i ∈ (f_{i-1}·minFrequencyRatio,
///   f_{i+1}/minFrequencyRatio)`，因此任意拖拽都无法把两段频点
///   挪到一起——切分永远不会重叠；
/// - 每段带宽 `w_i = 2·min(f_i − L_i, R_i − f_i)`，即半带宽（约
///   半增益点）永远落在自己拥有的区间内，绝不踩进邻段的地盘；
/// - 相邻两段的钟形响应在共享边界处交汇（各自约贡献一半增益），
///   合成曲线是连续的斜坡——频段之间平滑过渡，而不是直上直下的台阶。
class EqualizerBandModel {
  EqualizerBandModel({
    required List<double> frequencies,
    required List<double> gainsDb,
  }) : assert(frequencies.length == bandCount),
       assert(gainsDb.length == bandCount),
       _frequencies = List.unmodifiable(frequencies),
       _gainsDb = List.unmodifiable(gainsDb);

  /// 频段数（固定 8 段）。
  static const int bandCount = 8;

  /// 可调频域下限 / 上限（Hz）。
  static const double minFrequency = 20;
  static const double maxFrequency = 20000;

  /// 单段增益范围（dB）。
  static const double minGainDb = -12;
  static const double maxGainDb = 12;

  /// 相邻频点的最小频率比（约 1.3 个半音）。频点间隔的下限，
  /// 从根源上杜绝两段中心频率重叠。
  static const double minFrequencyRatio = 1.1;

  /// 带宽下限（Hz）。仅用于兜底「频点贴着切分边界 ⇒ 自然带宽趋于 0」
  /// 的退化情形（如首段拖到 20 Hz）。
  ///
  /// 这个值**必须**小于任何频段在几何切分边界一侧的最小空间的一半：
  /// 该空间 ≥ f·(√minFrequencyRatio−1) ≥ 0.976 Hz（f=20 时取到最小），
  /// 内段自然带宽恒 ≥ 2·f·(1−1/√1.1) ≥ 2.05 Hz——因此 1.0 Hz 的下限
  /// 永远不会把 -3dB 足点顶出切分区间，防重叠不变量才严格成立。
  static const double _minBandwidthHz = 1.0;

  /// 默认频点（Hz）：32 → 10k，接近对数等距，覆盖全可听域。
  static const List<double> defaultFrequencies = [
    32, 64, 125, 250, 500, 1000, 3000, 10000, //
  ];

  final List<double> _frequencies;
  final List<double> _gainsDb;

  /// 8 段中心频率（Hz），严格递增。
  List<double> get frequencies => _frequencies;

  /// 8 段增益（dB）。
  List<double> get gainsDb => _gainsDb;

  /// 全部增益为 0、频点为默认值的平坦模型。
  factory EqualizerBandModel.flat() => EqualizerBandModel(
    frequencies: defaultFrequencies,
    gainsDb: List<double>.filled(bandCount, 0),
  );

  /// 频段 i 拥有的区间左界（与左邻的几何中点；首段为 20 Hz）。
  double regionLeft(int i) =>
      i == 0 ? minFrequency : math.sqrt(_frequencies[i - 1] * _frequencies[i]);

  /// 频段 i 拥有的区间右界（与右邻的几何中点；末段为 20 kHz）。
  double regionRight(int i) => i == bandCount - 1
      ? maxFrequency
      : math.sqrt(_frequencies[i] * _frequencies[i + 1]);

  /// 频段 i 的带宽（Hz，anequalizer 的 `w=` 语义）。
  ///
  /// 取「到两侧切分边界较近者距离」的两倍：半带宽恰好止步于自己的
  /// 切分区间内，相邻频段在共享边界处衔接，互不重叠。
  double bandwidthOf(int i) {
    final f = _frequencies[i];
    final half = math.min(f - regionLeft(i), regionRight(i) - f);
    return math.max(2 * half, _minBandwidthHz);
  }

  /// 频段 i 的 Q 值（`Q = f / w`），仅用于响应计算与展示。
  double qOf(int i) {
    final w = bandwidthOf(i);
    return w <= 0 ? 1 : _frequencies[i] / w;
  }

  /// 频段 i 的钟形响应在 [freq] 处的增益（dB）。
  ///
  /// peaking 滤波器的模拟原型（与 RBJ 双二进制数字实现一致）：
  /// `x = freq / f0`，`A = 10^(g/40)`：
  /// `|H|² = ((1−x²)² + (A·x/Q)²) / ((1−x²)² + (x/(A·Q))²)`，
  /// 增益 dB = 10·log10(|H|²)。在中心频率处恰好等于 g。
  double bandGainDbAt(int i, double freq) {
    final g = _gainsDb[i];
    if (g == 0) return 0;
    final x = freq / _frequencies[i];
    final a = math.pow(10, g / 40).toDouble();
    final q = qOf(i);
    final one = 1 - x * x;
    final num = one * one + (a * x / q) * (a * x / q);
    final den = one * one + (x / (a * q)) * (x / (a * q));
    if (den <= 0 || num <= 0) return 0;
    return 10 * (math.log(num / den) / math.ln10);
  }

  /// 全链合成响应（dB）：anequalizer 各段级联，dB 域直接相加。
  double combinedGainDbAt(double freq) {
    var total = 0.0;
    for (var i = 0; i < bandCount; i++) {
      total += bandGainDbAt(i, freq);
    }
    return total;
  }

  /// 频段 i 的中心频率可调区间 `(low, high)`：
  /// 与左右邻各保持 [minFrequencyRatio] 的最小间隔，
  /// 首段下界 20 Hz、末段上界 20 kHz。
  (double, double) frequencyRange(int i) {
    final low = i == 0 ? minFrequency : _frequencies[i - 1] * minFrequencyRatio;
    final high = i == bandCount - 1
        ? maxFrequency
        : _frequencies[i + 1] / minFrequencyRatio;
    return (low, high);
  }

  /// 返回修改频段 i 后的新模型；频率 / 增益自动收敛到合法区间。
  ///
  /// 单段复位 / 归零也走这里（传 `gainDb: 0`，频点保留）。
  EqualizerBandModel withBand(int i, {double? frequency, double? gainDb}) {
    final freqs = List<double>.of(_frequencies);
    final gains = List<double>.of(_gainsDb);
    if (frequency != null) {
      final (low, high) = frequencyRange(i);
      freqs[i] = frequency.clamp(low, high).toDouble();
    }
    if (gainDb != null) {
      gains[i] = gainDb.clamp(minGainDb, maxGainDb).toDouble();
    }
    return EqualizerBandModel(frequencies: freqs, gainsDb: gains);
  }

  /// 转成引擎侧的 anequalizer 配置。
  ///
  /// 每段输出为 peaking 频段（c0/c1 双通道、Butterworth `t=0`），
  /// 带宽由频段切分**实时推导**——因此盘上只需持久化频点与增益，
  /// 改动频点后带宽自动跟随，不存在带宽与频点失配的中间态。
  mpv.AnequalizerSettings toAnequalizerSettings({required bool enabled}) {
    final bands = <mpv.AnequalizerBand>[
      for (var i = 0; i < bandCount; i++)
        mpv.AnequalizerBand(
          frequency: _frequencies[i],
          bandwidth: bandwidthOf(i),
          gain: _gainsDb[i],
        ),
    ];
    return (const mpv.AnequalizerSettings())
        .withBands(bands)
        .copyWith(enabled: enabled);
  }

  /// 从引擎侧配置恢复模型。
  ///
  /// 带宽字段被忽略（由频点重新推导）；频点 / 增益损坏（无序、越界、
  /// 不满足最小间隔）时整体退回平坦默认，绝不让坏数据炸掉页面。
  static EqualizerBandModel fromAnequalizerSettings(
    mpv.AnequalizerSettings? settings,
  ) {
    final model = EqualizerBandModel.flat();
    if (settings == null) return model;
    final bands = settings.bands;
    if (bands.length < bandCount) return model;

    final freqs = List<double>.of(defaultFrequencies);
    final gains = List<double>.filled(bandCount, 0);
    for (var i = 0; i < bandCount; i++) {
      freqs[i] = bands[i].frequency;
      gains[i] = bands[i].gain.clamp(minGainDb, maxGainDb).toDouble();
    }
    if (!_isValid(freqs)) return model;
    return EqualizerBandModel(frequencies: freqs, gainsDb: gains);
  }

  /// 频点合法性校验：全局界内、严格递增且满足最小间隔。
  static bool _isValid(List<double> freqs) {
    for (var i = 0; i < freqs.length; i++) {
      if (freqs[i] < minFrequency || freqs[i] > maxFrequency) return false;
      if (i > 0 && freqs[i] < freqs[i - 1] * minFrequencyRatio * 0.999) {
        return false;
      }
    }
    return true;
  }
}
