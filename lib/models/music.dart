import 'package:http/http.dart' as http;
import 'dart:convert';

class Music {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final Duration? duration;
  final String audioUrl;
  final List<Page> pages;
  final bool isFavorite;

  Music({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.duration,
    required this.audioUrl,
    this.pages = const [],
    this.isFavorite = false,
  });

  factory Music.fromJson(Map<String, dynamic> json) {
    List<Page> pagesList = [];
    if (json['pages'] != null) {
      var list = json['pages'] as List;
      pagesList = list.map((i) => Page.fromJson(i)).toList();
    }

    return Music(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album']?.toString() ?? '未知专辑',
      coverUrl: json['coverUrl']?.toString().trim().isEmpty ?? true
              ? 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png'
              : json['coverUrl'],
      duration: json['duration'] != null ? Duration(seconds: int.parse(json['duration'])) : null,
      audioUrl: json['audioUrl']?.toString() ?? '',
      pages: pagesList,
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'duration': duration?.inSeconds.toString() ?? '300',
      'audioUrl': audioUrl,
      'pages': pages.map((page) => page.toJson()).toList(),
      'isFavorite': isFavorite,
    };
  }

  /// 获取视频详情
  Future<Music> getVideoDetails() async {
    // 如果已经有持续时间，不需要重新获取
    if (duration != null && duration!.inSeconds > 0) {
      return Music(
        id: id,
        title: title,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        duration: duration,
        audioUrl: audioUrl,
        pages: pages,
        isFavorite: isFavorite, // 保持收藏状态
      );
    }
    
    // 否则从网络获取详细信息
    final response = await http.get(Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$id'));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['code'] == 0) {
        final data = json['data'];
        final pagesData = data['pages'] ?? [];
        final pagesList = pagesData.map<Page>((pageJson) => Page.fromJson(pageJson)).toList();
        
        // 更新duration为第一个分P的时长
        final newDuration = pagesList.isNotEmpty 
          ? Duration(seconds: int.parse(pagesList[0].duration))
          : const Duration(seconds: 180);

        return Music(
          id: id,
          title: title.isEmpty ? data['title'] : title,
          artist: artist.isEmpty ? data['owner']['name'] : artist,
          album: album.isEmpty ? (data['album'] ?? '未知专辑') : album,
          coverUrl: coverUrl.isEmpty ? data['pic'] + "@672w_378h" : coverUrl,
          duration: newDuration,
          audioUrl: audioUrl,
          pages: pagesList,
          isFavorite: isFavorite, // 保持收藏状态
        );
      }
    }
    return this; // 如果获取失败保持原样
  }

  /// 创建一个新的Music对象，更新收藏状态
  Music copyWith({bool? isFavorite}) {
    return Music(
      id: id,
      title: title,
      artist: artist,
      album: album,
      coverUrl: coverUrl,
      duration: duration,
      audioUrl: audioUrl,
      pages: pages,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  static bool isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    return Uri.tryParse(url)?.hasAbsolutePath == true;
  }
  
  String get safeCoverUrl =>
      isValidImageUrl(coverUrl) ? coverUrl : 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png';
}

class Page {
  final String cid;
  final String duration;
  final String part;

  Page({
    required this.cid,
    required this.duration,
    required this.part,
  });

  factory Page.fromJson(Map<String, dynamic> json) {
    return Page(
      cid: json['cid'].toString(),
      duration: json['duration'].toString(),
      part: json['part'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cid': cid,
      'duration': duration,
      'part': part,
    };
  }
}