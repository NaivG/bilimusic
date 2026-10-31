import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/related_video.dart';

/// 版权音乐「热歌榜」的一期条目。
///
/// 一条目由两部分组成：
///   - 歌曲维度的榜单信息（歌名 / 歌手 / 专辑 / 热度 / 排名），只用于热歌榜
///     列表的行头渲染；
///   - 一条可播放的相关视频（`creation_*` 字段），[toMusic] 直接以它的
///     标题 / UP 主 / 封面 / 时长构造 [Music]。
///
/// `can_listen` 一类的版权音源字段不在这里：本项目只能播 B 站稿件，
/// 官方音源能不能听与播放链路无关。
class HotSong {
  /// 本期排名，从 1 开始。
  final int rank;

  /// 上期排名；0 表示上期不在榜（新上榜）。
  final int lastRank;

  /// 版权音乐 id（`MA...`），仅作去重键使用。
  final String musicId;

  /// 歌名。
  final String title;

  /// 歌手，合唱用逗号分隔。
  final String singer;

  /// 专辑名，接口可能为空。
  final String album;

  /// 榜单歌曲封面（`mv_cover`），缺失时回退相关视频封面。
  final String coverUrl;

  /// 热度值（榜单口径，不是播放量）。
  final int heat;

  /// 相关视频时长（秒）。
  final int durationSeconds;

  /// 可直接播放的相关视频 bvid；空串表示本期没有可用稿件。
  final String bvid;

  /// 相关视频的首 P cid，拿到即可直接取流。
  final String cid;

  /// 相关视频的身份信息；[bvid] 为空时为 null。
  final RelatedVideo? relatedVideo;

  /// 榜单给的成就标签，如「重回榜单」「最高排名1」。
  final List<String> achievements;

  const HotSong({
    required this.rank,
    this.lastRank = 0,
    this.musicId = '',
    required this.title,
    required this.singer,
    this.album = '',
    this.coverUrl = '',
    this.heat = 0,
    this.durationSeconds = 0,
    this.bvid = '',
    this.cid = '',
    this.relatedVideo,
    this.achievements = const [],
  });

  /// 是否能播（没有相关视频就只能看名字）。
  bool get isPlayable => bvid.isNotEmpty;

  /// 相对上期的名次变化：正数上升、负数下降、null 表示新上榜。
  int? get rankDelta => lastRank <= 0 ? null : lastRank - rank;

  /// 榜单行头的副标题：「歌手 - 专辑」，与 [Music.subtitleText] 同一分隔符。
  String get subtitleText => album.trim().isEmpty
      ? singer
      : '${singer.isEmpty ? '未知歌手' : singer} - $album';

  /// 转成可播放的曲目：元数据全部取相关视频。
  ///
  /// 歌名 / 歌手 / 专辑只属于榜单行头，不能带进播放链路，否则播放页显示的
  /// 是一首歌、实际播的却是另一条投稿。
  Music toMusic() {
    final video = relatedVideo;
    return Music(
      id: bvid,
      cid: cid,
      title: video?.title ?? '',
      artist: Artist(
        mid: video?.uploaderMid ?? 0,
        name: video?.uploaderName ?? '',
      ),
      album: '',
      coverUrl: video?.coverUrl ?? '',
      duration: durationSeconds > 0 ? Duration(seconds: durationSeconds) : null,
      audioUrl: '',
    );
  }

  /// 解析 `copyright-music-publicity/toplist/music_list` 的单条。
  factory HotSong.fromToplistJson(Map<String, dynamic> json) {
    final mvCover = (json['mv_cover'] ?? '').toString().trim();
    final creationCover = (json['creation_cover'] ?? '').toString().trim();
    final achievements = json['achievements'];
    final cid = _asInt(json['creation_first_cid']);
    final bvid = (json['creation_bvid'] ?? '').toString();
    return HotSong(
      rank: _asInt(json['rank']),
      lastRank: _asInt(json['last_rank']),
      musicId: (json['music_id'] ?? '').toString(),
      title: (json['music_title'] ?? '').toString(),
      singer: (json['singer'] ?? '').toString(),
      album: (json['album'] ?? '').toString(),
      coverUrl: mvCover.isNotEmpty ? mvCover : creationCover,
      heat: _asInt(json['heat']),
      durationSeconds: _asInt(json['creation_duration']),
      bvid: bvid,
      // cid=0 表示接口没给，留空让播放链路自己补，别当成合法分P
      cid: cid > 0 ? '$cid' : '',
      relatedVideo: bvid.isEmpty
          ? null
          : RelatedVideo(
              bvid: bvid,
              title: (json['creation_title'] ?? '').toString(),
              uploaderName: (json['creation_nickname'] ?? '').toString(),
              uploaderMid: _asInt(json['creation_up']),
              playCount: _asInt(json['creation_play']),
              coverUrl: creationCover,
            ),
      achievements: achievements is List
          ? achievements.map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// 从落盘缓存回读（字段名与 [toJson] 对齐）。
  factory HotSong.fromJson(Map<String, dynamic> json) {
    final achievements = json['achievements'];
    final bvid = (json['bvid'] ?? '').toString();
    final storedVideo = json['relatedVideo'];
    return HotSong(
      rank: _asInt(json['rank']),
      lastRank: _asInt(json['lastRank']),
      musicId: (json['musicId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      singer: (json['singer'] ?? '').toString(),
      album: (json['album'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      heat: _asInt(json['heat']),
      durationSeconds: _asInt(json['durationSeconds']),
      bvid: bvid,
      cid: (json['cid'] ?? '').toString(),
      relatedVideo: bvid.isEmpty
          ? null
          : storedVideo is Map
          ? RelatedVideo.fromJson(Map<String, dynamic>.from(storedVideo))
          : RelatedVideo(bvid: bvid),
      achievements: achievements is List
          ? achievements.map((e) => e.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'lastRank': lastRank,
    'musicId': musicId,
    'title': title,
    'singer': singer,
    'album': album,
    'coverUrl': coverUrl,
    'heat': heat,
    'durationSeconds': durationSeconds,
    'bvid': bvid,
    'cid': cid,
    'relatedVideo': relatedVideo?.toJson(),
    'achievements': achievements,
  };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
