import 'dart:math' as math;

import 'package:bilimusic/features/player/logic/equalizer_bands.dart';

/// 均衡器预设：面向新手的「一键听感」，按「听感预设」与「耳机校准」
/// 两组呈现在预设菜单里。
///
/// 两种定义方式、：
/// - **听感预设**走 [EqualizerPreset.fromCurve]：给出**频点锚点**与
///   **目标响应曲线**（若干控制点），增益在锚点处对曲线采样得到
///   （log 频率域线性插值）。预设定义里只有「想要什么形状」，
///   频点由各预设自定义
///   [EqualizerBandModel.defaultFrequencies] 的默认 8 段。
/// - **耳机校准**（Harman / AutoEq 目标补偿）是外部参考数据，按 8 段
///   直接采好写死，测试里钉住原始数值防止被误改。
///
/// 新增预设只在这里加一条 + 在 `test/player/equalizer_presets_test.dart`
/// 里加对应断言；不动 [EqualizerBandModel] 与引擎侧 anequalizer 配置通路。

/// 目标响应曲线的一个控制点（频点 Hz · 增益 dB）。
typedef EqCurvePoint = ({double freq, double gain});

/// 在 [frequencies] 上对目标曲线 [curve] 采样，得到各频段增益（dB）。
///
/// [curve] 按频点**升序**给出控制点；相邻控制点之间在
/// log(频率)–dB 平面上线性插值（音频上「对数频率轴线性 dB」就是
/// 感知上最平滑的过渡），区间外取最近端点的值。
List<double> sampleEqCurve(List<double> frequencies, List<EqCurvePoint> curve) {
  assert(curve.length >= 2, '目标曲线至少需要两个控制点');
  for (var i = 1; i < curve.length; i++) {
    assert(curve[i].freq > curve[i - 1].freq, '控制点频点必须严格递增');
  }
  return [for (final f in frequencies) _sampleAt(f, curve)];
}

double _sampleAt(double f, List<EqCurvePoint> curve) {
  if (f <= curve.first.freq) return curve.first.gain;
  for (var i = 1; i < curve.length; i++) {
    final prev = curve[i - 1];
    final next = curve[i];
    if (f <= next.freq) {
      final t =
          (math.log(f) - math.log(prev.freq)) /
          (math.log(next.freq) - math.log(prev.freq));
      return prev.gain + t * (next.gain - prev.gain);
    }
  }
  return curve.last.gain;
}

/// 均衡器预设。
class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.model,
  });

  /// 听感预设的构造入口：频点锚点 + 目标响应曲线。
  ///
  /// 增益在锚点处对曲线采样得到，频点由预设自己决定——
  /// 定义处不出现魔法小数，也不绑定默认 8 段频点。
  factory EqualizerPreset.fromCurve({
    required String id,
    required String name,
    required String description,
    required List<double> frequencies,
    required List<EqCurvePoint> curve,
  }) {
    return EqualizerPreset(
      id: id,
      name: name,
      description: description,
      model: _validatedModel(frequencies, sampleEqCurve(frequencies, curve)),
    );
  }

  /// 预设标识（小写、稳定、英文，测试与文档引用它）。
  final String id;

  /// UI 展示名（中文）。
  final String name;

  /// 一句话说明。
  final String description;

  /// 8 段 peaking 模型。频点由各预设自定义（不必统一用默认 8 段）；
  /// Q 由模型内部自动推导。
  final EqualizerBandModel model;
}

/// 构造预设模型并自检频点合法性：debug 下断言即时暴露，
/// release 下由 `equalizer_presets_test.dart` 的全量校验兜底。
EqualizerBandModel _validatedModel(
  List<double> frequencies,
  List<double> gainsDb,
) {
  final model = EqualizerBandModel(frequencies: frequencies, gainsDb: gainsDb);
  assert(
    model.hasValidFrequencies,
    '预设频点不合法：需在 ${EqualizerBandModel.minFrequency}–'
    '${EqualizerBandModel.maxFrequency} Hz 内、严格递增且相邻比 ≥ '
    '${EqualizerBandModel.minFrequencyRatio}',
  );
  return model;
}

/// 预设分组：菜单里按组渲染，组标题作分隔。
class EqualizerPresetGroup {
  const EqualizerPresetGroup({required this.title, required this.presets});

  /// 组标题（如「听感预设」）。
  final String title;

  /// 组内预设。
  final List<EqualizerPreset> presets;
}

/// 内置预设（按组组织）。
final List<EqualizerPresetGroup> kEqualizerPresetGroups = [
  EqualizerPresetGroup(
    title: '听感预设',
    presets: [
      // 低频从 20 Hz 的 +5 dB 平滑收到 1.6 kHz 归零：
      // 低音厚实但不糊中频。频点锚定在低频侧。
      EqualizerPreset.fromCurve(
        id: 'fullerBass',
        name: '饱满低音',
        description: '低频厚实、增加温暖感',
        frequencies: [40, 80, 160, 320, 640, 1250, 2500, 5000],
        curve: [
          (freq: 20, gain: 5),
          (freq: 160, gain: 4),
          (freq: 400, gain: 1.5),
          (freq: 800, gain: 0.3),
          (freq: 1600, gain: 0),
          (freq: 20000, gain: 0),
        ],
      ),
      // 低频小幅抬升 + 300 Hz 附近挖浅槽 + 3–4 kHz 临场峰：
      // 经典的「鲜活」整形，人声与主奏前推。
      EqualizerPreset.fromCurve(
        id: 'energetic',
        name: '鲜活突出',
        description: '低音与临场感前推、更有侵略感',
        frequencies: [63, 125, 250, 500, 1000, 2000, 4000, 8000],
        curve: [
          (freq: 20, gain: 2),
          (freq: 300, gain: -1.5),
          (freq: 1000, gain: 0),
          (freq: 4000, gain: 3),
          (freq: 8000, gain: 1),
          (freq: 20000, gain: 0),
        ],
      ),
      // 300 Hz 挖浊 + 3 kHz 临场峰 + 6–7 kHz 空气感：人声更清晰。
      EqualizerPreset.fromCurve(
        id: 'crispVocals',
        name: '清晰人声',
        description: '去除低中频浑浊、提升齿音清晰度',
        frequencies: [50, 100, 200, 400, 800, 1600, 3150, 6300],
        curve: [
          (freq: 20, gain: 0),
          (freq: 120, gain: -0.5),
          (freq: 300, gain: -3),
          (freq: 800, gain: 0),
          (freq: 3000, gain: 3.5),
          (freq: 7000, gain: 1.5),
          (freq: 20000, gain: 0),
        ],
      ),
      // 2.5 kHz 起高频缓降（6 kHz 齿音区 -3、10 kHz 以上 -3.5）：
      // 削掉金属感与齿音，久听不累。
      EqualizerPreset.fromCurve(
        id: 'smoothRelaxed',
        name: '柔和耐听',
        description: '削减齿音与金属感，长时间聆听不疲劳',
        frequencies: [63, 125, 250, 500, 1000, 2000, 4000, 8000],
        curve: [
          (freq: 20, gain: 0),
          (freq: 1000, gain: 0),
          (freq: 3000, gain: -1.5),
          (freq: 6000, gain: -3),
          (freq: 10000, gain: -3.5),
          (freq: 20000, gain: -3),
        ],
      ),
      // 深夜模式：60 Hz 以下的隆隆声穿墙最凶，砍掉；3 kHz 附近小幅
      // 抬升补小音量下的清晰度；超高频略收，避免夜里的刺耳感。
      EqualizerPreset.fromCurve(
        id: 'lateNight',
        name: '夜深人静',
        description: '削减低频与高频，小音量也听得清',
        frequencies: [40, 80, 160, 320, 640, 1250, 2500, 5000],
        curve: [
          (freq: 20, gain: -4),
          (freq: 60, gain: -4),
          (freq: 200, gain: -1),
          (freq: 1000, gain: 0.5),
          (freq: 3000, gain: 1.5),
          (freq: 8000, gain: 0),
          (freq: 20000, gain: -1),
        ],
      ),
      // 胆机味：150–400 Hz 宽缓隆起 + 8 kHz 以上缓收，
      // 模拟电子管放大器的温暖染色。
      EqualizerPreset.fromCurve(
        id: 'tubeAmp',
        name: '胆机温暖',
        description: '模拟电子管放大器的谐波温暖',
        frequencies: [50, 100, 200, 400, 800, 1600, 3200, 6400],
        curve: [
          (freq: 20, gain: 0.5),
          (freq: 150, gain: 1.5),
          (freq: 400, gain: 1.5),
          (freq: 1000, gain: 1),
          (freq: 3000, gain: 0.5),
          (freq: 8000, gain: -0.5),
          (freq: 20000, gain: -1),
        ],
      ),
    ],
  ),
  EqualizerPresetGroup(
    title: '耳机校准',
    presets: [
      // 参考数据：Harman / AutoEq 目标补偿曲线的 8 段采样，
      // 适用于频响接近平直的耳机，把它们拉向对应目标曲线。
      EqualizerPreset(
        id: 'harman-over-ear-2018',
        name: 'Harman Over-Ear 2018',
        description: '把平直头戴耳机拉向 Harman 头戴目标曲线',
        model: _validatedModel(
          [26.3, 47.2, 215.4, 505.8, 1046.1, 3242.2, 6648.4, 12843.1],
          [2.08, 1.53, -4.30, -2.12, -2.55, 7.16, 1.75, -7.84],
        ),
      ),
      EqualizerPreset(
        id: 'harman-in-ear-2019',
        name: 'Harman In-Ear 2019',
        description: '把平直入耳耳机拉向 Harman 入耳目标曲线',
        model: _validatedModel(
          [27.7, 51.2, 252.0, 604.8, 1127.2, 3073.8, 5976.9, 10964.8],
          [4.93, 3.22, -5.17, -3.68, -2.89, 6.43, 3.08, -5.66],
        ),
      ),
      EqualizerPreset(
        id: 'autoeq-in-ear',
        name: 'AutoEq In-Ear',
        description: '按 AutoEq 入耳平均目标补偿校准',
        model: _validatedModel(
          [28.9, 64.9, 146.7, 325.6, 772.4, 3011.0, 6716.3, 12219.8],
          [-1.78, -1.49, -1.49, -1.58, -1.31, 8.04, 4.31, -5.70],
        ),
      ),
    ],
  ),
];
