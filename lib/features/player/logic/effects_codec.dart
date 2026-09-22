import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// 把 [AudioEffects] 中「UI 精选子集」编码 / 解码成可 JSON 化的 Map，
/// 用于效果包的**独立持久化**（SharedPreferences 键
/// `player_audio_effects_v1`，见 `AudioEffectsService`）。
///
/// 编码格式与 mpv_studio 的 EffectsCodec 同构（eq / comp / bass /
/// treble / crossfeed / crystalizer / stereo / subboost / loudnorm），
/// 之外再加本项目自己的 `aneq`（8 段均衡）与音效增强 / 立体声增强两组
/// （`exciter` / `echo` / `limiter` / `surround`）。只编码 UI 暴露的
/// 模块；bundle 里其余效果保持禁用默认值。解码空表 / 缺键的 Map 时缺什么
/// 补什么默认值，格式向前向后兼容——以后新增效果配置项，只需扩展
/// encode/decode 两个方法，旧数据无损。
///
/// **encode 只写「UI 暴露的字段」就够了**：decode 对没编码的字段一律用
/// 构造默认值重建，而这些槽位只由本文件创建，未编码字段永远停在默认值上，
/// 所以 `decode(encode(e)) == e` 成立（回归见
/// `test/player/effects_codec_test.dart`）。**一旦别处给未编码字段赋了
/// 非默认值，这个不变量就断了**——那时要么把该字段加进 encode，要么改掉
/// 那处赋值。
///
/// `aneq` 是本项目自己的扩展（8 段可调频段均衡器，见
/// `EqualizerBandModel`），mpv_studio 的编解码器没有这个键；
/// 旧版本落盘数据缺 `aneq` 时按默认值补齐。
///
/// `echo` 存 lavfi 的 `decays` / `delays` **原始列表串**（不是拆开的数字）：
/// 编码侧读到什么就写什么、解码侧原样回填，roundtrip 才不会被字符串格式
/// 化改动（详见 `AechoParams`）。
class EffectsCodec {
  EffectsCodec._();

  static double _d(Object? v, double fallback) =>
      (v as num?)?.toDouble() ?? fallback;
  static bool _b(Object? v, bool fallback) => v as bool? ?? fallback;
  static String _s(Object? v, String fallback) => v as String? ?? fallback;
  static Map<String, Object?> _m(Object? v) =>
      v is Map ? v.cast<String, Object?>() : const {};

  static Map<String, Object?> encode(AudioEffects e) {
    // 0.4.0 起槽位可空（null = 从未配置）：把没配过的也按默认值编码，
    // 让落盘格式形状稳定；disabled 但配置过参数的槽位原样保留参数
    // （关闭只把它从 af 链摘掉，不丢参数）。
    final superequalizer = e.superequalizer ?? const SuperequalizerSettings();
    final anequalizer = e.anequalizer ?? const AnequalizerSettings();
    final acompressor = e.acompressor ?? const AcompressorSettings();
    final bass = e.bass ?? const BassSettings();
    final treble = e.treble ?? const TrebleSettings();
    final crossfeed = e.crossfeed ?? const CrossfeedSettings();
    final crystalizer = e.crystalizer ?? const CrystalizerSettings();
    final extrastereo = e.extrastereo ?? const ExtrastereoSettings();
    final asubboost = e.asubboost ?? const AsubboostSettings();
    final aexciter = e.aexciter ?? const AexciterSettings();
    final aecho = e.aecho ?? const AechoSettings();
    final alimiter = e.alimiter ?? const AlimiterSettings();
    final surround = e.surround ?? const SurroundSettings();
    final loudnorm = e.loudnorm ?? const LoudnormSettings();
    return {
      'eq': {
        'enabled': superequalizer.enabled,
        'params': superequalizer.params,
      },
      // 8 段可调频段均衡器（设置 → 音频 → 音效与均衡器）。频点 / 增益
      // 存在 params CSV 里，带宽由 EqualizerBandModel 按切分实时推导，
      // 所以这里只透传 params 字符串即可。
      'aneq': {'enabled': anequalizer.enabled, 'params': anequalizer.params},
      'comp': {
        'enabled': acompressor.enabled,
        'threshold': acompressor.threshold,
        'ratio': acompressor.ratio,
        'attack': acompressor.attack,
        'release': acompressor.release,
        'makeup': acompressor.makeup,
        'knee': acompressor.knee,
      },
      'bass': {
        'enabled': bass.enabled,
        'gain': bass.gain,
        'frequency': bass.frequency,
      },
      'treble': {
        'enabled': treble.enabled,
        'gain': treble.gain,
        'frequency': treble.frequency,
      },
      'crossfeed': {
        'enabled': crossfeed.enabled,
        'strength': crossfeed.strength,
        'range': crossfeed.range,
      },
      'crystalizer': {'enabled': crystalizer.enabled, 'i': crystalizer.i},
      'stereo': {'enabled': extrastereo.enabled, 'm': extrastereo.m},
      'subboost': {
        'enabled': asubboost.enabled,
        'boost': asubboost.boost,
        'cutoff': asubboost.cutoff,
        'dry': asubboost.dry,
        'wet': asubboost.wet,
        'feedback': asubboost.feedback,
      },
      'exciter': {
        'enabled': aexciter.enabled,
        'amount': aexciter.amount,
        'drive': aexciter.drive,
        'freq': aexciter.freq,
      },
      // 原样存 lavfi 列表串（`|` 分隔），不拆成数字——见类文档。
      'echo': {
        'enabled': aecho.enabled,
        'decays': aecho.decays,
        'delays': aecho.delays,
        'in_gain': aecho.in_gain,
        'out_gain': aecho.out_gain,
      },
      'limiter': {
        'enabled': alimiter.enabled,
        'limit': alimiter.limit,
        'attack': alimiter.attack,
        'release': alimiter.release,
      },
      // surround 有 50+ 个 lavfi 参数，只编码 UI 暴露的声场姿态四项，
      // 其余（声道布局 / LFE / 窗函数…）一律停在构造默认值。
      'surround': {
        'enabled': surround.enabled,
        'angle': surround.angle,
        'focus': surround.focus,
        'overlap': surround.overlap,
        'smooth': surround.smooth,
      },
      'loudnorm': {
        'enabled': loudnorm.enabled,
        'i': loudnorm.i,
        'lra': loudnorm.lra,
        'tp': loudnorm.tp,
        'linear': loudnorm.linear,
      },
    };
  }

  static AudioEffects decode(Map<String, Object?> json) {
    final eq = _m(json['eq']);
    final aneq = _m(json['aneq']);
    final comp = _m(json['comp']);
    final bass = _m(json['bass']);
    final treble = _m(json['treble']);
    final crossfeed = _m(json['crossfeed']);
    final crystalizer = _m(json['crystalizer']);
    final stereo = _m(json['stereo']);
    final subboost = _m(json['subboost']);
    final exciter = _m(json['exciter']);
    final echo = _m(json['echo']);
    final limiter = _m(json['limiter']);
    final surround = _m(json['surround']);
    final loudnorm = _m(json['loudnorm']);

    final eqParams = <String, double>{};
    _m(eq['params']).forEach((k, v) {
      if (v is num) eqParams[k] = v.toDouble();
    });

    return AudioEffects(
      superequalizer: SuperequalizerSettings(
        enabled: _b(eq['enabled'], false),
        params: eqParams,
      ),
      anequalizer: AnequalizerSettings(
        enabled: _b(aneq['enabled'], false),
        params: (aneq['params'] as String?) ?? '',
      ),
      acompressor: AcompressorSettings(
        enabled: _b(comp['enabled'], false),
        threshold: _d(comp['threshold'], 0.125),
        ratio: _d(comp['ratio'], 2),
        attack: _d(comp['attack'], 20),
        release: _d(comp['release'], 250),
        makeup: _d(comp['makeup'], 1),
        knee: _d(comp['knee'], 2.82843),
      ),
      bass: BassSettings(
        enabled: _b(bass['enabled'], false),
        gain: _d(bass['gain'], 0),
        frequency: _d(bass['frequency'], 100),
      ),
      treble: TrebleSettings(
        enabled: _b(treble['enabled'], false),
        gain: _d(treble['gain'], 0),
        frequency: _d(treble['frequency'], 3000),
      ),
      crossfeed: CrossfeedSettings(
        enabled: _b(crossfeed['enabled'], false),
        strength: _d(crossfeed['strength'], 0.2),
        range: _d(crossfeed['range'], 0.5),
      ),
      crystalizer: CrystalizerSettings(
        enabled: _b(crystalizer['enabled'], false),
        i: _d(crystalizer['i'], 2),
      ),
      extrastereo: ExtrastereoSettings(
        enabled: _b(stereo['enabled'], false),
        m: _d(stereo['m'], 2.5),
      ),
      asubboost: AsubboostSettings(
        enabled: _b(subboost['enabled'], false),
        boost: _d(subboost['boost'], 2),
        cutoff: _d(subboost['cutoff'], 100),
        dry: _d(subboost['dry'], 1),
        wet: _d(subboost['wet'], 1),
        feedback: _d(subboost['feedback'], 0.9),
      ),
      loudnorm: LoudnormSettings(
        enabled: _b(loudnorm['enabled'], false),
        i: _d(loudnorm['i'], -24),
        lra: _d(loudnorm['lra'], 7),
        tp: _d(loudnorm['tp'], -2),
        linear: _b(loudnorm['linear'], true),
      ),
      aexciter: AexciterSettings(
        enabled: _b(exciter['enabled'], false),
        amount: _d(exciter['amount'], AexciterSettings.amountDefault),
        drive: _d(exciter['drive'], AexciterSettings.driveDefault),
        freq: _d(exciter['freq'], AexciterSettings.freqDefault),
      ),
      aecho: AechoSettings(
        enabled: _b(echo['enabled'], false),
        decays: _s(echo['decays'], const AechoSettings().decays),
        delays: _s(echo['delays'], const AechoSettings().delays),
        in_gain: _d(echo['in_gain'], AechoSettings.in_gainDefault),
        out_gain: _d(echo['out_gain'], AechoSettings.out_gainDefault),
      ),
      alimiter: AlimiterSettings(
        enabled: _b(limiter['enabled'], false),
        limit: _d(limiter['limit'], AlimiterSettings.limitDefault),
        attack: _d(limiter['attack'], AlimiterSettings.attackDefault),
        release: _d(limiter['release'], AlimiterSettings.releaseDefault),
      ),
      surround: SurroundSettings(
        enabled: _b(surround['enabled'], false),
        angle: _d(surround['angle'], SurroundSettings.angleDefault),
        focus: _d(surround['focus'], SurroundSettings.focusDefault),
        overlap: _d(surround['overlap'], SurroundSettings.overlapDefault),
        smooth: _d(surround['smooth'], SurroundSettings.smoothDefault),
      ),
    );
  }
}
