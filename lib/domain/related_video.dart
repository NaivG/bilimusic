/// 热歌榜条目实际播放的那条相关视频。
///
/// 榜单是歌曲维度的（歌名 / 歌手 / 专辑），可播放的却是 `creation_*` 描述的
/// 一条投稿视频：标题、UP 主、封面、播放量都属于视频，与榜单歌曲不是同一实体。
///
/// 歌曲信息只用于热歌榜列表的行头渲染；进入播放链路的一律是本模型，
/// 由 `HotSong.toMusic()` 转成 `Music`。
class RelatedVideo {
  /// 稿件 bvid，等于播放曲目的 id。
  final String bvid;

  /// 稿件标题，可能与榜单歌名完全不同。
  final String title;

  /// 稿件 UP 主昵称。
  final String uploaderName;

  /// 稿件 UP 主 mid；0 表示接口没给。
  final int uploaderMid;

  /// 稿件播放量；0 表示接口没给。
  final int playCount;

  /// 稿件封面；空串表示接口没给。
  final String coverUrl;

  const RelatedVideo({
    required this.bvid,
    this.title = '',
    this.uploaderName = '',
    this.uploaderMid = 0,
    this.playCount = 0,
    this.coverUrl = '',
  });

  factory RelatedVideo.fromJson(Map<String, dynamic> json) => RelatedVideo(
    bvid: (json['bvid'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    uploaderName: (json['uploaderName'] ?? '').toString(),
    uploaderMid: _asInt(json['uploaderMid']),
    playCount: _asInt(json['playCount']),
    coverUrl: (json['coverUrl'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'bvid': bvid,
    'title': title,
    'uploaderName': uploaderName,
    'uploaderMid': uploaderMid,
    'playCount': playCount,
    'coverUrl': coverUrl,
  };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
