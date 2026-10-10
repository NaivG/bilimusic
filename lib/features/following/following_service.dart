import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/bili_following.dart';

/// 「查看关注」的数据编排：关注列表分页。
///
/// 网络细节全在 [ApiService]（一个端点一个方法），这里只负责翻页参数。
/// UP 主投稿的拉取与聚合在 artist 特性域的 `ArtistService`（歌手页的数据源）。
class FollowingService {
  FollowingService({required this.api});

  final ApiService api;

  /// 关注列表每页条数（接口默认 50，这里保持一致）。
  static const int followingPageSize = 50;

  /// 拉一页关注列表。返回 `(items, total)`；失败时是空页 + total 0。
  Future<({List<BiliFollowing> items, int total})> fetchFollowingsPage({
    required int vmid,
    int page = 1,
    bool byAttention = false,
  }) {
    return api.fetchFollowings(
      vmid,
      page: page,
      pageSize: followingPageSize,
      byAttention: byAttention,
    );
  }
}
