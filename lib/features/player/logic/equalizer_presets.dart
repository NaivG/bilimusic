import 'package:bilimusic/features/player/logic/equalizer_bands.dart';

/// 均衡器预设（面向新手的"一键听感"）。
class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.model,
  });

  /// 落盘键（小写、稳定、英文）。
  final String id;

  /// UI 展示名（中文）。
  final String name;

  /// 一句话说明。
  final String description;

  /// 8 段 peaking 模型。频点固定为默认 8 段；Q 由模型内部自动推导。
  final EqualizerBandModel model;
}

/// 内置预设列表。
///
/// 新增预设只在这里加一条 + 在测试里加对应断言；
/// 不动 [EqualizerBandModel] 与引擎侧 anequalizer 配置通路。
final List<EqualizerPreset> kBuiltInEqualizerPresets = [
  EqualizerPreset(
    id: 'fullerBass',
    name: '饱满低音',
    description: '低频厚实、增加温暖感',
    model: EqualizerBandModel(
      frequencies: EqualizerBandModel.defaultFrequencies,
      gainsDb: [3.229, 2.879, 2.531, 2.413, 1.24, 0.551, 0.161, 0.044],
    ),
  ),
  EqualizerPreset(
    id: 'energetic',
    name: '鲜活突出',
    description: '人声与主奏乐器前推、更有侵略感',
    model: EqualizerBandModel(
      frequencies: EqualizerBandModel.defaultFrequencies,
      gainsDb: [0.04, 0.081, 0.16, 0.328, 0.696, 1.708, 3.236, 1.56],
    ),
  ),
  EqualizerPreset(
    id: 'crispVocals',
    name: '清晰人声',
    description: '去除低中频浑浊、提升齿音清晰度',
    model: EqualizerBandModel(
      frequencies: EqualizerBandModel.defaultFrequencies,
      gainsDb: [-0.166, -0.346, -0.785, -1.849, -0.554, 0.278, 3.729, 0.989],
    ),
  ),
  EqualizerPreset(
    id: 'smoothRelaxed',
    name: '柔和耐听',
    description: '削减齿音与金属感，长时间聆听不疲劳',
    model: EqualizerBandModel(
      frequencies: EqualizerBandModel.defaultFrequencies,
      gainsDb: [-0.022, -0.043, -0.084, -0.169, -0.345, -0.748, -2.295, -1.096],
    ),
  ),
  EqualizerPreset(
    id: 'lateNight',
    name: '夜深人静',
    description: '低音量补偿（Fletcher-Munson）',
    model: EqualizerBandModel(
      frequencies: EqualizerBandModel.defaultFrequencies,
      gainsDb: [-3.374, -2.635, -1.361, 0.544, 0.691, 0.231, -0.389, -1.562],
    ),
  ),
  EqualizerPreset(
    id: 'tubeAmp',
    name: '胆机温暖',
    description: '模拟电子管放大器的谐波温暖',
    model: EqualizerBandModel(
      frequencies: EqualizerBandModel.defaultFrequencies,
      gainsDb: [0.319, 0.645, 1.25, 1.546, 1.048, 1.04, 0.422, -0.49],
    ),
  ),
];
