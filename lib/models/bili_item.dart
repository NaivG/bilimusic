import 'package:bilimusic/models/music.dart';

/// BiliItem - 视频级模型，用于卡片展示
/// 每个视频（bvid）对应一个 BiliItem，包含视频基础信息和分P列表 List<Music>
/// 卡片渲染用 BiliItem，分P播放操作仍用 Music
class BiliItem {
  /// 稿件bvid
  final String bvid;

  /// 稿件标题
  final String title;

  /// 稿件封面
  final String pic;

  /// UP主信息
  final Owner owner;

  /// 视频统计数
  final Stat stat;

  /// 分P总数
  final int videos;

  /// 分区名称
  final String tname;

  /// 视频总时长（所有分P，单位秒）
  final int duration;

  /// 分P列表（每个分P对应一个 Music）
  final List<Music> pages;

  /// 投稿时间（秒级时间戳）
  final int pubdate;

  /// 渲染样式（透传给 Music）
  final MusicRenderStyle renderStyle;

  BiliItem({
    required this.bvid,
    required this.title,
    required this.pic,
    required this.owner,
    required this.stat,
    required this.videos,
    required this.tname,
    required this.duration,
    required this.pages,
    this.pubdate = 0,
    this.renderStyle = MusicRenderStyle.card,
  });

  /// 是否为多P视频
  bool get isSeries => pages.length > 1;

  /// 获取当前选中的分P
  Music? get currentPage {
    if (pages.isEmpty) return null;
    return pages.first;
  }

  /// 获取指定分P的 cid
  String? pageCidAt(int index) {
    if (index < 0 || index >= pages.length) return null;
    return pages[index].cid.isNotEmpty ? pages[index].cid : null;
  }

  /// 获取指定分P的时长
  Duration? pageDurationAt(int index) {
    if (index < 0 || index >= pages.length) return null;
    return pages[index].duration;
  }

  /// 获取指定分P
  Music? pageAt(int index) {
    if (index < 0 || index >= pages.length) return null;
    return pages[index];
  }

  /// 安全封面
  String get safeCoverUrl => Music.isValidImageUrl(pic)
      ? pic
      : 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png';

  /// 格式化总时长
  String get formattedDuration {
    final d = Duration(seconds: duration);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 从 API x/web-interface/view 响应构造
  factory BiliItem.fromViewApi(Map<String, dynamic> data) {
    final pagesData = (data['pages'] ?? []) as List;
    final ownerData = data['owner'] ?? {};
    final statData = data['stat'] ?? {};

    final pages = pagesData.asMap().entries.map<Music>((entry) {
      final idx = entry.key;
      final pageJson = entry.value;
      // 单P时标题用视频标题，多P时用分P标题
      final isSingle = pagesData.length == 1;
      final pageCid = pageJson['cid']?.toString() ?? '';
      return Music(
        id: data['bvid'] ?? '',
        cid: pageCid,
        title: isSingle ? (data['title'] ?? '') : (pageJson['part'] ?? pageJson['title'] ?? ''),
        artist: ownerData['name'] ?? '未知作者',
        album: data['title'] ?? '未知专辑',
        coverUrl: data['pic'] ?? '',
        duration: Duration(seconds: int.tryParse(pageJson['duration']?.toString() ?? '0') ?? 0),
        audioUrl: '',
        isFavorite: false,
        currentPageIndex: idx,
        renderStyle: MusicRenderStyle.card,
      );
    }).toList();

    return BiliItem(
      bvid: data['bvid'] ?? '',
      title: data['title'] ?? '',
      pic: data['pic'] ?? '',
      owner: Owner(
        mid: ownerData['mid']?.toString() ?? '0',
        name: ownerData['name'] ?? '未知作者',
        face: ownerData['face'] ?? '',
      ),
      stat: Stat(
        view: statData['view'] ?? 0,
        like: statData['like'] ?? 0,
        danmaku: statData['danmaku'] ?? 0,
        reply: statData['reply'] ?? 0,
        favorite: statData['favorite'] ?? 0,
        coin: statData['coin'] ?? 0,
        share: statData['share'] ?? 0,
        nowRank: statData['now_rank'] ?? 0,
        hisRank: statData['his_rank'] ?? 0,
       vt: statData['vt'] ?? 0,
      ),
      videos: data['videos'] ?? 1,
      tname: data['tname'] ?? '',
      duration: data['duration'] ?? 0,
      pages: pages,
      pubdate: data['pubdate'] ?? 0,
    );
  }

  /// 获取视频详情（填充音频URL等）
  /// [resolveAudioUrl] 回调用于解析每个分P的音频URL
  Future<BiliItem> fetchAudioUrls({
    required Future<String> Function(Music music) resolveAudioUrl,
  }) async {
    if (pages.isEmpty) return this;

    // 批量解析每个分P的音频URL，保留失败时的原对象
    final updatedPages = await Future.wait(
      pages.map((music) async {
        try {
          final url = await resolveAudioUrl(music);
          return music.withAudioUrl(url);
        } catch (e) {
          return music;
        }
      }),
    );

    return copyWith(pages: updatedPages);
  }

  /// 创建副本
  BiliItem copyWith({
    String? bvid,
    String? title,
    String? pic,
    Owner? owner,
    Stat? stat,
    int? videos,
    String? tname,
    int? duration,
    List<Music>? pages,
    int? pubdate,
    MusicRenderStyle? renderStyle,
  }) {
    return BiliItem(
      bvid: bvid ?? this.bvid,
      title: title ?? this.title,
      pic: pic ?? this.pic,
      owner: owner ?? this.owner,
      stat: stat ?? this.stat,
      videos: videos ?? this.videos,
      tname: tname ?? this.tname,
      duration: duration ?? this.duration,
      pages: pages ?? this.pages,
      pubdate: pubdate ?? this.pubdate,
      renderStyle: renderStyle ?? this.renderStyle,
    );
  }
}

/// UP主信息
class Owner {
  final String mid;
  final String name;
  final String face;

  Owner({
    required this.mid,
    required this.name,
    required this.face,
  });

  factory Owner.fromJson(Map<String, dynamic> json) {
    return Owner(
      mid: json['mid']?.toString() ?? '0',
      name: json['name'] ?? '未知作者',
      face: json['face'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'mid': mid, 'name': name, 'face': face};
}

/// 视频统计数
class Stat {
  final int view;
  final int like;
  final int danmaku;
  final int reply;
  final int favorite;
  final int coin;
  final int share;
  final int nowRank;
  final int hisRank;
  final int vt;

  Stat({
    required this.view,
    required this.like,
    required this.danmaku,
    required this.reply,
    required this.favorite,
    required this.coin,
    required this.share,
    required this.nowRank,
    required this.hisRank,
    this.vt = 0,
  });

  factory Stat.fromJson(Map<String, dynamic> json) {
    return Stat(
      view: json['view'] ?? 0,
      like: json['like'] ?? 0,
      danmaku: json['danmaku'] ?? 0,
      reply: json['reply'] ?? 0,
      favorite: json['favorite'] ?? 0,
      coin: json['coin'] ?? 0,
      share: json['share'] ?? 0,
      nowRank: json['now_rank'] ?? 0,
      hisRank: json['his_rank'] ?? 0,
      vt: json['vt'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'view': view,
        'like': like,
        'danmaku': danmaku,
        'reply': reply,
        'favorite': favorite,
        'coin': coin,
        'share': share,
        'now_rank': nowRank,
        'his_rank': hisRank,
        'vt': vt,
      };

  /// 格式化播放量
  String get formattedView => _formatCount(view);
  /// 格式化点赞数
  String get formattedLike => _formatCount(like);
  /// 格式化收藏数
  String get formattedFavorite => _formatCount(favorite);
  /// 格式化投币数
  String get formattedCoin => _formatCount(coin);
  /// 格式化分享数
  String get formattedShare => _formatCount(share);

  static String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }
}
