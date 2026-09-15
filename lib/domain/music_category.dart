/// B 站音乐分区的 tid 集合（含主分区与子分区）。
///
/// 从 `RecommendationManager._isMusicCategory` 抽出，供 RoamingService
/// 在过滤 `/archive/related` 返回结果时复用。
const musicTids = <int>{
  3,
  28,
  29,
  30,
  31,
  59,
  130,
  193,
  243,
  244,
  265,
  266,
  267,
};

/// 判断给定 tid 是否属于音乐分区。
bool isMusicCategory(int? tid) => tid != null && musicTids.contains(tid);
