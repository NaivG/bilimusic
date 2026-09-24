/// 自动淡入淡出策略：根据当前曲目时长推导 crossfade 的时长与触发位置。
///
/// 纯 Dart，无 Flutter / 播放引擎依赖。
///
/// 设计：
/// - **时长**：fade 时长取曲目时长的固定比例（[durationRatio]），夹在
///   [minFadeMs]–[maxFadeMs] 之间。短曲（B 站切片）自动缩短、长曲（电台
///   混音）自动加长，避免固定时长两头不讨好。
/// - **位置**：fade-out 恰好覆盖曲目的最后 fadeMs 毫秒——触发点就是
///   「曲目结尾往前 fadeMs」。位置由时长唯一导出，不单独设旋钮：
///   过渡早了吃掉结尾，晚了拖进下一首，只有「结尾前 fadeMs」是正确落点。
class CrossfadeAuto {
  const CrossfadeAuto._();

  /// fade 时长占曲目时长的比例：3%（每 20 秒时长对应 1 秒过渡）。
  ///
  /// 30 秒切片 → 0.9 秒；1 分钟 → 1.8 秒；3 分钟 → 5.4 秒；
  /// 5 分 30 秒以上 → 封顶 10 秒。
  static const double durationRatio = 0.03;

  /// fade 时长下限（毫秒）。极短曲目至少给 1 秒，否则过渡不可感知。
  static const int minFadeMs = 1000;

  /// fade 时长上限（毫秒）。与手动滑块的 1–10 秒范围对齐。
  static const int maxFadeMs = 10000;

  /// 曲目时长未知（0 / 负数）时的退化值，与手动模式默认值一致。
  static const int fallbackFadeMs = 3000;

  /// 根据曲目时长计算 fade 时长（毫秒）。
  ///
  /// 触发位置 = 曲目结尾往前本返回值（见 PlayerCoordinator 的
  /// `_checkPreloadTrigger`）；若进入过渡窗口时剩余时间已不足本值
  /// （预加载比预期慢），调用方会把 fade 收紧到剩余时间。
  static int fadeDurationMs(Duration trackDuration) {
    final ms = trackDuration.inMilliseconds;
    if (ms <= 0) return fallbackFadeMs;
    return (ms * durationRatio).round().clamp(minFadeMs, maxFadeMs);
  }
}
