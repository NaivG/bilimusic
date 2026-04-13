import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 网易云音乐信息类
class NeteaseMusicInfo {
  final String id;
  final String name;
  final String artist;

  NeteaseMusicInfo({
    required this.id,
    required this.name,
    required this.artist,
  });

  @override
  String toString() {
    return 'NeteaseMusicInfo(id: $id, name: $name, artist: $artist)';
  }
}

/// 网易云音乐API工具类
class NeteaseMusicApi {
  static const String _baseUrl = 'https://music.163.com';
  static const String _searchApi = '/api/search/get/web';
  static const String _lyricApi = '/api/song/lyric';

  // 网易云音乐API专用headers
  static final Map<String, String> _apiHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Referer': _baseUrl,
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  // 歌词缓存管理器
  static final CacheManager _lyricCacheManager = CacheManager(
    Config(
      'lyric_cache',
      stalePeriod: Duration(days: 30), // 歌词缓存30天
      maxNrOfCacheObjects: 200, // 最多缓存200首歌词
    ),
  );

  /// 搜索音乐并返回前5-10个结果的名称和ID集合
  ///
  /// [keyword] 搜索关键词（音乐名称）
  /// 返回音乐信息列表
  static Future<List<NeteaseMusicInfo>> searchMusic(String keyword) async {
    try {
      final uri = Uri.parse('$_baseUrl$_searchApi');
      final response = await http
          .post(
            uri,
            headers: _apiHeaders,
            body: {
              'csrf_token': '',
              'hlpretag': '',
              'hlposttag': '',
              's': keyword,
              'type': '1', // 1: 单曲
              'offset': '0',
              'total': 'true',
              'limit': '10', // 获取前10个结果
            },
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 200 && data['result'] != null) {
          final songs = data['result']['songs'] as List?;
          if (songs != null && songs.isNotEmpty) {
            // 提取前5-10个歌曲的信息
            final musicList = <NeteaseMusicInfo>[];
            final takeCount = songs.length > 10 ? 10 : songs.length;
            final minCount = 5;

            for (
              int i = 0;
              i < (takeCount > minCount ? takeCount : minCount) &&
                  i < songs.length;
              i++
            ) {
              final song = songs[i];
              if (song['id'] != null) {
                final id = song['id'].toString();
                final name = song['name']?.toString() ?? '未知歌曲';
                final artist = (song['artists'] as List?)?.isNotEmpty == true
                    ? song['artists'][0]['name']?.toString() ?? '未知艺术家'
                    : '未知艺术家';

                musicList.add(
                  NeteaseMusicInfo(id: id, name: name, artist: artist),
                );
              }
            }
            return musicList;
          }
        }
      }
    } catch (e) {
      debugPrint('搜索音乐时出错: $e');
    }
    return [];
  }

  /// 根据音乐ID获取歌词
  ///
  /// [musicId] 音乐ID
  /// 返回歌词内容，如果缓存中有则直接返回缓存内容
  static Future<String?> getLyric(String musicId) async {
    try {
      // 首先尝试从缓存中获取
      final cachedLyric = await _getCachedLyric(musicId);
      if (cachedLyric != null) {
        return cachedLyric;
      }

      // 缓存中没有，则从网络获取
      final uri = Uri.parse('$_baseUrl$_lyricApi?id=$musicId&lv=-1&tv=-1');
      final response = await http
          .get(uri, headers: _apiHeaders)
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 200 && data['lrc'] != null) {
          final lyric = data['lrc']['lyric'] as String?;
          if (lyric != null && lyric.isNotEmpty) {
            // 缓存歌词
            await _cacheLyric(musicId, lyric);
            return lyric;
          }
        }
      }
    } catch (e) {
      debugPrint('获取歌词时出错: $e');
    }
    return null;
  }

  /// 从缓存中获取歌词
  static Future<String?> _getCachedLyric(String musicId) async {
    try {
      final fileInfo = await _lyricCacheManager.getFileFromCache(musicId);
      if (fileInfo != null) {
        final file = fileInfo.file;
        if (await file.exists()) {
          return await file.readAsString();
        }
      }
    } catch (e) {
      debugPrint('从缓存读取歌词时出错: $e');
    }
    return null;
  }

  /// 缓存歌词
  static Future<void> _cacheLyric(String musicId, String lyric) async {
    try {
      // 将歌词字符串转换为字节数据
      final bytes = Uint8List.fromList(utf8.encode(lyric));

      // 使用putFile方法将字节数据添加到缓存管理器
      await _lyricCacheManager.putFile(musicId, bytes, fileExtension: 'txt');
    } catch (e) {
      debugPrint('缓存歌词时出错: $e');
    }
  }
}
