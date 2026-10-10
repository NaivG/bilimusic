import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/bili_following.dart';
import 'package:bilimusic/domain/music.dart';

/// 「查看关注」的数据编排：关注列表分页 + 把某位 UP 主的投稿攒成一个临时歌单。
/// 网络细节全在 [ApiService]（一个端点一个方法），这里只负责翻页聚合。
class FollowingService {
  FollowingService({required this.api});

  final ApiService api;

  /// 关注列表每页条数（接口默认 50，这里保持一致）。
  static const int followingPageSize = 50;

  /// 临时歌单最多装多少首。
  /// 
  /// 除了老登还有索大款，其他应该不会触碰这个。
  static const int maxSongs = 90;

  /// UP 主投稿每页条数（接口默认 30）。
  static const int songPageSize = 30;

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

  /// 把某个 UP 主的投稿聚合成临时歌单的曲目列表（按最新发布倒序）。
  ///
  /// 逐页拉到 [maxSongs] 首、或遇到不满一页（到底）、或某一页空为止。
  /// [onProgress] 回传 `(已拿到, 总数)`，给页面显示加载进度用。
  Future<List<Music>> collectUserSongs(
    BiliFollowing up, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    final album = '${up.name} 的投稿';
    final songs = <Music>[];
    var page = 1;

    while (songs.length < maxSongs) {
      final result = await api.fetchUserSpaceVideos(
        up.mid,
        page: page,
        pageSize: songPageSize,
        album: album,
      );

      if (result.songs.isEmpty) break;
      songs.addAll(result.songs);
      onProgress?.call(songs.length, result.total);

      // 不满一页 = 没有下一页
      if (result.songs.length < songPageSize) break;
      page++;
    }

    return songs.length > maxSongs ? songs.sublist(0, maxSongs) : songs;
  }
}
