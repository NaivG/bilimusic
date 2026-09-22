import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

/// lavfi `aecho` 的 delays / decays 列表串 ↔ 单值换算。
///
/// 这两个参数在 lavfi 里是 **`|` 分隔的列表**（一个回声配一段延迟 + 一段
/// 衰减），落到 mpv_audio_kit 上只能是 [String] 字段。本项目的 UI 只暴露
/// **单回声**，于是需要一层读写换算：
///
/// - **读**（[firstOf]）：取第一段。多段历史数据也能安全降级，解析不出来
///   回传 fallback，绝不让坏数据炸掉设置页；
/// - **写**（[single]）：写单值，且**整数不带小数点**（`1000` 而不是
///   `1000.0`）。`AechoSettings.toFilterString()` 判「是否非默认」是拿字符串
///   和 `'1000'` 比，写成 `'1000.0'` 会让默认值看起来变了，每次都重建一次
///   af 链——滑动条松手就断一下音，纯属自找。
///
/// 纯函数、不 import Flutter、不持有引擎状态，可直接单测
/// （见 `test/player/echo_settings_test.dart`）。
class AechoParams {
  AechoParams._();

  /// 取 lavfi 列表串的第一段；空串 / null / 解析不出来都回 [fallback]。
  static double firstOf(String? list, double fallback) {
    if (list == null || list.isEmpty) return fallback;
    final head = list.split(RegExp(r'[|,]')).first.trim();
    if (head.isEmpty) return fallback;
    return double.tryParse(head) ?? fallback;
  }

  /// 把单值写回 lavfi 列表串（整数省掉小数点，保持与默认串同形）。
  static String single(double value) {
    final rounded = value.roundToDouble();
    return value == rounded ? rounded.toInt().toString() : '$value';
  }

  /// 当前包里 aecho 的延迟（ms）。未配置时回 lavfi 默认串再解析一次，
  /// 这样默认值永远跟着 [mpv.AechoSettings] 的构造默认走，不会两边各写一份。
  static double delayOf(mpv.AechoSettings? settings) =>
      firstOf(settings?.delays ?? const mpv.AechoSettings().delays, 1000);

  /// 当前包里 aecho 的衰减（0..1 的响度比）。同 [delayOf]。
  static double decayOf(mpv.AechoSettings? settings) =>
      firstOf(settings?.decays ?? const mpv.AechoSettings().decays, 0.5);
}
