import 'dart:math' as math;

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

/// 动态范围压缩器（lavfi `acompressor`）的纯逻辑模型。
///
/// 古典 / 现场录音的动态范围往往很大（ppp ↔ fff 高 低合唱要差 30+ dB），
/// 在耳机或小音量环境下听感不友好。`acompressor` 在阈值之上按比例缩小
/// 动态，让弱音更易被听见、强音不爆。
///
/// 本类只承载 UI 要交互的 5 个字段：threshold（dB）/ ratio / attack（ms）
/// / release（ms）/ makeup（dB）。其余 lavfi 参数（`knee` 的 factor、
/// `level_in` / `level_out` / `link` / `mode` / `detection`）走 mpv_audio_kit
/// 默认值——`knee` 默认 2.82843（factor，约 9 dB 软拐）已经对绝大多数
/// 录音合适，UI 不暴露避免用户调出硬拐听感劣化。
///
/// - **threshold / makeup 在内部用 dB 存储**——UI 与用户认知一致（dB 是
///   「响度」的自然单位）；落盘 / 下发到 lavfi 时再 `dbToAmplitude` 转
///   线性 amplitude，避免在 UI 边界反复换算引入舍入误差。
/// - 不 import Flutter、不持有引擎状态——落盘与下发走 `effects_providers.dart`
///   的效果包链路（AudioEffects.acompressor 槽位）；
/// - 与 [mpv.AcompressorSettings] 通过 [toAcompressorSettings] /
///   [fromAcompressorSettings] 互转，round-trip 应当完全保真。
class CompressorSettingsModel {
  CompressorSettingsModel({
    required double thresholdDb,
    required double ratio,
    required double attackMs,
    required double releaseMs,
    required double makeupDb,
  }) : _thresholdDb = thresholdDb
           .clamp(_thresholdMinDb, _thresholdMaxDb)
           .toDouble(),
       _ratio = ratio
           .clamp(
             mpv.AcompressorSettings.ratioMin,
             mpv.AcompressorSettings.ratioMax,
           )
           .toDouble(),
       _attackMs = attackMs
           .clamp(
             mpv.AcompressorSettings.attackMin,
             mpv.AcompressorSettings.attackMax,
           )
           .toDouble(),
       _releaseMs = releaseMs
           .clamp(
             mpv.AcompressorSettings.releaseMin,
             mpv.AcompressorSettings.releaseMax,
           )
           .toDouble(),
       _makeupDb = makeupDb.clamp(_makeupMinDb, _makeupMaxDb).toDouble();

  /// 默认：阈值 -18 dB（lavfi 默认 0.125 amplitude → ≈ -18 dB）/
  /// 压缩比 2:1 / 起音 20 ms / 释音 250 ms / 补正 0 dB。
  ///
  /// 与 lavfi `acompressor` 的 default 一致（除 knee 也走默认）。
  factory CompressorSettingsModel.defaults() => CompressorSettingsModel(
    thresholdDb: amplitudeToDb(mpv.AcompressorSettings.thresholdDefault),
    ratio: mpv.AcompressorSettings.ratioDefault,
    attackMs: mpv.AcompressorSettings.attackDefault,
    releaseMs: mpv.AcompressorSettings.releaseDefault,
    makeupDb: 0,
  );

  /// 全部参数为默认值的平坦模型（用于"重置"按钮）。
  factory CompressorSettingsModel.flat() => CompressorSettingsModel.defaults();

  // ── 内部常量（threshold / makeup 用 dB 边界）────────────────────────

  /// threshold 在 UI 上显示的范围（dB）。下限取 −60 dB（人耳阈附近）、
  /// 上限取 0 dBFS（数字满刻度，再上去就是 clipping）。
  static const double _thresholdMinDb = -60;
  static const double _thresholdMaxDb = 0;

  /// makeup 在 UI 上显示的范围（dB）。lavfi 下限是 1×（0 dB）、上限
  /// 64×（≈ 36 dB），但 24 dB 已远超实用范围（会把底噪一起拉满），
  /// UI 上限取 24 dB 即可，再大听感必劣化。
  static const double _makeupMinDb = 0;
  static const double _makeupMaxDb = 24;

  final double _thresholdDb;
  final double _ratio;
  final double _attackMs;
  final double _releaseMs;
  final double _makeupDb;

  /// 阈值（dB）：信号高于此值开始压缩。
  double get thresholdDb => _thresholdDb;

  /// 压缩比（1..20）：输入每涨 N dB，输出涨 1 dB。1.0 = 透传（不压缩）。
  double get ratio => _ratio;

  /// 起音（ms）：信号越过阈值后多久完成衰减。
  double get attackMs => _attackMs;

  /// 释音（ms）：信号跌回阈值后多久回到不压缩状态。
  double get releaseMs => _releaseMs;

  /// 补正增益（dB）：压完再往回加多少，补偿被压掉的响度。
  double get makeupDb => _makeupDb;

  CompressorSettingsModel withThresholdDb(double thresholdDb) =>
      CompressorSettingsModel(
        thresholdDb: thresholdDb,
        ratio: _ratio,
        attackMs: _attackMs,
        releaseMs: _releaseMs,
        makeupDb: _makeupDb,
      );

  CompressorSettingsModel withRatio(double ratio) => CompressorSettingsModel(
    thresholdDb: _thresholdDb,
    ratio: ratio,
    attackMs: _attackMs,
    releaseMs: _releaseMs,
    makeupDb: _makeupDb,
  );

  CompressorSettingsModel withAttackMs(double attackMs) =>
      CompressorSettingsModel(
        thresholdDb: _thresholdDb,
        ratio: _ratio,
        attackMs: attackMs,
        releaseMs: _releaseMs,
        makeupDb: _makeupDb,
      );

  CompressorSettingsModel withReleaseMs(double releaseMs) =>
      CompressorSettingsModel(
        thresholdDb: _thresholdDb,
        ratio: _ratio,
        attackMs: _attackMs,
        releaseMs: releaseMs,
        makeupDb: _makeupDb,
      );

  CompressorSettingsModel withMakeupDb(double makeupDb) =>
      CompressorSettingsModel(
        thresholdDb: _thresholdDb,
        ratio: _ratio,
        attackMs: _attackMs,
        releaseMs: _releaseMs,
        makeupDb: makeupDb,
      );

  /// 转成引擎侧的 acompressor 配置。
  ///
  /// threshold / makeup 从 dB 转线性 amplitude（lavfi 的 wire 格式），
  /// 其余字段透传数值；`knee / level_in / level_sc / link / mode / detection /
  ///   mix` 一律走 mpv_audio_kit 默认值（不暴露给用户，codec 也只编码这 6 项），
  /// 见 `effects_codec.dart`。
  mpv.AcompressorSettings toAcompressorSettings({required bool enabled}) {
    return mpv.AcompressorSettings(
      enabled: enabled,
      threshold: dbToAmplitude(_thresholdDb).clamp(
        mpv.AcompressorSettings.thresholdMin,
        mpv.AcompressorSettings.thresholdMax,
      ),
      ratio: _ratio,
      attack: _attackMs,
      release: _releaseMs,
      makeup: dbToAmplitude(_makeupDb).clamp(
        mpv.AcompressorSettings.makeupMin,
        mpv.AcompressorSettings.makeupMax,
      ),
    );
  }

  /// 从引擎侧配置恢复模型。
  ///
  /// 损坏 / 越界 / null 时整体回退默认，绝不让坏数据炸掉页面。
  static CompressorSettingsModel fromAcompressorSettings(
    mpv.AcompressorSettings? settings,
  ) {
    if (settings == null) return CompressorSettingsModel.flat();
    return CompressorSettingsModel(
      thresholdDb: amplitudeToDb(settings.threshold),
      ratio: settings.ratio,
      attackMs: settings.attack,
      releaseMs: settings.release,
      makeupDb: amplitudeToDb(settings.makeup),
    );
  }

  // ── 振幅 ↔ dB 换算（公开，方便可视化 widget 复用）─────────────────────

  /// 线性振幅 → dB（电压·20·log10；lavfi 内部用振幅，不用功率）。
  ///
  /// `amp <= 0` 时返回 `floor`（默认 −120 dB，约等于浮点零的下界），
  /// 防止 log10 报 -inf 拖脏整条曲线。振幅为 0 在物理上代表数字静音，
  /// 无意义也无所谓 — 反正不会出现在有效信号里。
  static double amplitudeToDb(double amp, {double floor = -120}) {
    if (amp <= 0) return floor;
    final db = 20 * (math.log(amp) / math.ln10);
    return db < floor ? floor : db;
  }

  /// dB → 线性振幅（`10^(db/20)`）。
  static double dbToAmplitude(double db) => math.pow(10, db / 20).toDouble();
}
