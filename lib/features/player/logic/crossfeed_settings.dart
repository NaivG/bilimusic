import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

/// 交叉回馈（lavfi `crossfeed`）的纯逻辑模型。
///
/// 头戴耳机听音时，左右声道直接抵达各自耳朵——与音箱经空气串扰到达对侧
/// 的真实听感不同，会造成「声场被钉在脑内」的感觉。`crossfeed` 把对侧
/// 通道混一小份进来，模拟音箱的串扰。
///
/// 本类只承载 UI 要交互的 2 个字段：strength（混多少对侧通道）/ range
/// （低架截频对应的声场宽度）；`enabled` 由调用方在转换时传入。
/// 其余 lavfi 参数（`level_in` / `level_out` / `slope` / `block_size`）
/// 走 mpv_audio_kit 默认值，不暴露给用户。
///
/// 字段边界由 [mpv.CrossfeedSettings] 的常量定义（`strengthMin/Max`、
///   `rangeMin/Max`），UI 显示范围（百分比 0..100%）与底层的 0..1 直接对应。
///
/// - 不 import Flutter、不持有引擎状态——落盘与下发走 `effects_providers.dart`
///   的效果包链路（AudioEffects.crossfeed 槽位）；
/// - 与 [mpv.CrossfeedSettings] 通过 [toCrossfeedSettings] /
///   [fromCrossfeedSettings] 互转，round-trip 应当完全保真。
class CrossfeedSettingsModel {
  CrossfeedSettingsModel({required double strength, required double range})
    : _strength = strength
          .clamp(
            mpv.CrossfeedSettings.strengthMin,
            mpv.CrossfeedSettings.strengthMax,
          )
          .toDouble(),
      _range = range
          .clamp(mpv.CrossfeedSettings.rangeMin, mpv.CrossfeedSettings.rangeMax)
          .toDouble();

  /// 默认：轻微混音（strength=0.2）、中等宽度（range=0.5），与 lavfi 默认一致。
  factory CrossfeedSettingsModel.defaults() => CrossfeedSettingsModel(
    strength: mpv.CrossfeedSettings.strengthDefault,
    range: mpv.CrossfeedSettings.rangeDefault,
  );

  /// 全部参数为默认值的平坦模型（用于"重置"按钮）。
  factory CrossfeedSettingsModel.flat() => CrossfeedSettingsModel.defaults();

  final double _strength;
  final double _range;

  /// 对侧混音强度（0..1）：越大越像音箱听感，1.0 为 lavfi 最大值。
  double get strength => _strength;

  /// 声场宽度（0..1）：越大低架截频越高、串扰覆盖的频段越宽。
  double get range => _range;

  CrossfeedSettingsModel withStrength(double strength) =>
      CrossfeedSettingsModel(strength: strength, range: _range);

  CrossfeedSettingsModel withRange(double range) =>
      CrossfeedSettingsModel(strength: _strength, range: range);

  /// 转成引擎侧的 crossfeed 配置。
  ///
  /// 落盘的 `level_in / level_out / slope / block_size` 一律沿用 mpv_audio_kit
  /// 默认值（不与用户的 strength/range 操作重叠），codec 侧也只透传 strength/
  /// range 两个字段——见 `effects_codec.dart`。
  mpv.CrossfeedSettings toCrossfeedSettings({required bool enabled}) {
    return mpv.CrossfeedSettings(
      enabled: enabled,
      strength: _strength,
      range: _range,
    );
  }

  /// 从引擎侧配置恢复模型。
  ///
  /// 损坏 / 越界 / null 时整体回退默认，绝不让坏数据炸掉页面。
  static CrossfeedSettingsModel fromCrossfeedSettings(
    mpv.CrossfeedSettings? settings,
  ) {
    if (settings == null) return CrossfeedSettingsModel.flat();
    return CrossfeedSettingsModel(
      strength: settings.strength,
      range: settings.range,
    );
  }
}
