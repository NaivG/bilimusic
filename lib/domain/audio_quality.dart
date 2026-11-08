/// B 站音频流的音质档位。
///
/// 只描述「是哪一档」，不掺 UI：徽标怎么画、设置页怎么排版都由消费方决定。
enum AudioQualityKind {
  /// 标准 AAC（64K / 132K / 192K）。
  standard,

  /// Hi-Res 无损（FLAC）。
  hiResLossless,

  /// 杜比全景声。
  dolbyAtmos,
}

/// 一个音质档位的展示信息。
///
/// `id` 是取流接口的音质代码（30xxx）；未知代码按 192K HQ 兜底，与设置页
/// 「不可用时自动选最高可用音质」的默认值一致。
class AudioQualityInfo {
  const AudioQualityInfo({
    required this.id,
    required this.label,
    required this.kind,
  });

  /// 取流接口的音质代码。
  final String id;

  /// 中文档位描述，设置页与徽标共用。
  final String label;

  final AudioQualityKind kind;

  /// 杜比全景声在徽标里只画字标，不重复中文文案。
  bool get showsLabel => kind != AudioQualityKind.dolbyAtmos;

  /// 无损档位才画 ALAC 波形标志。
  bool get showsLosslessIcon => kind == AudioQualityKind.hiResLossless;

  static const AudioQualityInfo hiResLossless = AudioQualityInfo(
    id: '30251',
    label: 'Hi-Res 无损',
    kind: AudioQualityKind.hiResLossless,
  );

  static const AudioQualityInfo dolbyAtmos = AudioQualityInfo(
    id: '30250',
    label: '杜比全景声',
    kind: AudioQualityKind.dolbyAtmos,
  );

  static const AudioQualityInfo hq192 = AudioQualityInfo(
    id: '30280',
    label: '192K HQ',
    kind: AudioQualityKind.standard,
  );

  static const AudioQualityInfo sq132 = AudioQualityInfo(
    id: '30232',
    label: '132K SQ',
    kind: AudioQualityKind.standard,
  );

  static const AudioQualityInfo he64 = AudioQualityInfo(
    id: '30216',
    label: '64K AAC-HE',
    kind: AudioQualityKind.standard,
  );

  /// 兜底档位（设置页默认值）。
  static const AudioQualityInfo fallback = hq192;

  static const Map<String, AudioQualityInfo> _byId = <String, AudioQualityInfo>{
    '30251': hiResLossless,
    '30250': dolbyAtmos,
    '30280': hq192,
    '30232': sq132,
    '30216': he64,
  };

  /// 按音质代码取档位；未知代码返回 [fallback]。
  static AudioQualityInfo of(String qualityId) => _byId[qualityId] ?? fallback;
}
