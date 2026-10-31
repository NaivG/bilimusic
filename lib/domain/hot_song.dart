import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';

/// 版权音乐「热歌榜」的一期条目。
///
/// 榜单是歌曲维度的（歌名 / 歌手 / 专辑 / 热度 / 排名），与 B 站稿件维度不同；
/// 每个条目都带一首可直接播放的创作稿件（`creation_bvid` + `creation_first_cid`），
/// 播放时用 [toMusic] 转成 [Music]。
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

  /// 封面：优先官方歌曲封面，缺失回退创作稿件封面。
  final String coverUrl;

  /// 热度值（榜单口径，不是播放量）。
  final int heat;

  /// 创作稿件时长（秒）。
  final int durationSeconds;

  /// 可直接播放的创作稿件 bvid；空串表示本期没有可用稿件。
  final String bvid;

  /// 创作稿件的首 P cid，拿到即可直接取流。
  final String cid;

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
    this.achievements = const [],
  });

  /// 是否能播（没有创作稿件就只能看名字）。
  bool get isPlayable => bvid.isNotEmpty;

  /// 相对上期的名次变化：正数上升、负数下降、null 表示新上榜。
  int? get rankDelta => lastRank <= 0 ? null : lastRank - rank;

  /// 「歌手 - 专辑」副标题，与 [Music.subtitleText] 同一分隔符。
  String get subtitleText => album.trim().isEmpty
      ? singer
      : '${singer.isEmpty ? '未知歌手' : singer} - $album';

  /// 转成可播放的曲目。
  ///
  /// `artist` 用歌手名而不是稿件 UP 主：热歌榜是歌曲榜，播放页显示的应该是
  /// 谁唱的。稿件 UP 归版权榜的 `creation_nickname`，与"这首歌归谁"无关。
  Music toMusic() => Music(
    id: bvid,
    cid: cid,
    title: title,
    artist: Artist(name: singer),
    album: album,
    coverUrl: coverUrl,
    duration: durationSeconds > 0 ? Duration(seconds: durationSeconds) : null,
    audioUrl: '',
  );

  /// 解析 `copyright-music-publicity/toplist/music_list` 的单条。
  factory HotSong.fromToplistJson(Map<String, dynamic> json) {
    final mvCover = (json['mv_cover'] ?? '').toString().trim();
    final creationCover = (json['creation_cover'] ?? '').toString().trim();
    final achievements = json['achievements'];
    final cid = _asInt(json['creation_first_cid']);
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
      bvid: (json['creation_bvid'] ?? '').toString(),
      // cid=0 表示接口没给，留空让播放链路自己补，别当成合法分P
      cid: cid > 0 ? '$cid' : '',
      achievements: achievements is List
          ? achievements.map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// 从落盘缓存回读（字段名与 [toJson] 对齐）。
  factory HotSong.fromJson(Map<String, dynamic> json) {
    final achievements = json['achievements'];
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
      bvid: (json['bvid'] ?? '').toString(),
      cid: (json['cid'] ?? '').toString(),
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
    'achievements': achievements,
  };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
