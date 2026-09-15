/// 漫游模式的歌曲挑选风格档位。
///
/// 离散 3 档（不是连续滑块），由用户在 profile_page 的 RoamSection 中选择。
/// 默认 [balanced]，可在 SettingsManager 中持久化。
enum RoamStyle { similar, balanced, explore }
