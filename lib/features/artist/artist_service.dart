import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/music.dart';

/// 歌手页（UP 页）的数据编排：拉某个 UP 主的投稿。
///
/// 网络细节全在 [ApiService]（一个端点一个方法），这里只负责分页参数与翻页聚合。
class ArtistService {
  ArtistService({required this.api});

  final ApiService api;

  /// 投稿列表每页条数（接口默认 30）。
  static const int submissionPageSize = 30;

  /// 攒队列时最多取多少首（播放全部 / 随机播放）。
  ///
  /// 除了老登还有索大款，其他应该不会触碰这个。
  static const int maxSongs = 90;

  /// 投稿曲目的 album（列表副标题的第二段）。
  static String albumOf(String upName) => '$upName 的投稿';

  /// 拉一页投稿（按最新发布倒序）。返回 `(songs, total)`；失败时是空页 + total 0。
  Future<({List<Music> songs, int total})> fetchSubmissionsPage({
    required int mid,
    required String upName,
    int page = 1,
  }) {
    return api.fetchUserSpaceVideos(
      mid,
      page: page,
      pageSize: submissionPageSize,
      album: albumOf(upName),
    );
  }

  /// 把投稿聚合成一份可整队列播放的曲目表（按最新发布倒序）。
  ///
  /// 逐页拉到 [maxSongs] 首、或遇到不满一页（到底）、或某一页空为止。
  /// [onProgress] 回传 `(已拿到, 总数)`，给页面显示加载进度用。
  Future<List<Music>> collectSubmissions({
    required int mid,
    required String upName,
    void Function(int loaded, int total)? onProgress,
  }) async {
    final songs = <Music>[];
    var page = 1;

    while (songs.length < maxSongs) {
      final result = await fetchSubmissionsPage(
        mid: mid,
        upName: upName,
        page: page,
      );

      if (result.songs.isEmpty) break;
      songs.addAll(result.songs);
      onProgress?.call(songs.length, result.total);

      // 不满一页 = 没有下一页
      if (result.songs.length < submissionPageSize) break;
      page++;
    }

    return songs.length > maxSongs ? songs.sublist(0, maxSongs) : songs;
  }
}
