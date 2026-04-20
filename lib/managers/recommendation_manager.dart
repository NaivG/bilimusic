import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/core/service_locator.dart';

class RecommendationManager {
  static final RecommendationManager _instance =
      RecommendationManager._internal();
  factory RecommendationManager() => _instance;
  RecommendationManager._internal();

  List<Music> _recommendedList = [];
  List<Music> _guessYouLikeList = [];
  DateTime? _lastUpdated;
  DateTime? _lastGuessUpdated;

  List<Music> get recommendedList => List.unmodifiable(_recommendedList);
  List<Music> get guessYouLikeList => List.unmodifiable(_guessYouLikeList);

  String get lastGuessUpdated =>
      _lastGuessUpdated?.toIso8601String().split('T').first ?? '从未更新';

  /// 加载推荐音乐列表
  Future<void> loadRecommendations() async {
    // 首先尝试从SharedPreferences加载缓存数据
    await _loadFromCache();
    if (_recommendedList.isNotEmpty) {
      return;
    }

    // 异步更新推荐列表
    await _updateRecommendations();
    debugPrint('推荐列表已更新');
  }

  /// 刷新推荐音乐列表
  Future<void> refreshRecommendations() async {
    await _updateRecommendations();
  }

  /// 更新猜你喜欢列表（基于播放历史）
  Future<void> updateGuessYouLike(List<Music> playHistory) async {
    // 检查是否需要更新（每天最多更新一次）
    if (_lastGuessUpdated != null &&
        DateTime.now().difference(_lastGuessUpdated!).inHours < 24) {
      return;
    }

    if (playHistory.isEmpty) return;

    // 取最近播放的5个视频作为参考
    final recentHistory = playHistory.length > 5
        ? playHistory.sublist(0, 5)
        : playHistory;

    final List<Music> guessList = [];
    final Set<String> addedIds = {}; // 避免重复添加

    for (var music in recentHistory) {
      if (guessList.length >= 20) break; // 最多20个推荐

      try {
        final response = await http.get(
          Uri.parse(
            'https://api.bilibili.com/x/web-interface/archive/related?bvid=${music.id}',
          ),
          headers: NetworkConfig.biliHeaders,
        );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          if (json['code'] == 0 && json['data'] != null) {
            final List<dynamic> relatedVideos = json['data'];

            for (var video in relatedVideos) {
              if (guessList.length >= 20) break;

              // 检查是否属于音乐分区 (tid 为音乐主分区或其子分区)
              final tid = video['tid'] as int?;
              if (_isMusicCategory(tid)) {
                final id = video['bvid'] ?? video['aid'].toString();

                // 避免重复
                if (addedIds.contains(id)) continue;
                addedIds.add(id);

                final albumName = video['tname'] ?? '未知专辑';

                final musicItem = Music(
                  id: id,
                  title: video['title'],
                  artist: video['owner']?['name'] ?? '未知艺术家',
                  album: albumName,
                  coverUrl: (video['pic'] ?? '') + "@672w_378h",
                  duration: null,
                  audioUrl: '',
                  pages: [],
                );

                guessList.add(musicItem);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('获取相关推荐失败: $e');
      }
    }

    _guessYouLikeList = guessList;
    _lastGuessUpdated = DateTime.now();

    // 保存到缓存
    await _saveGuessToCache();

    // 写入系统歌单
    await sl.playlistManager.addSongsToPlaylist(
      'recommended',
      _guessYouLikeList,
    );
  }

  /// 判断是否为音乐分类
  bool _isMusicCategory(int? tid) {
    if (tid == null) return false;

    // 音乐主分区和子分区的tid
    const musicTids = {
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
    return musicTids.contains(tid);
  }

  /// 更新推荐列表
  Future<void> _updateRecommendations() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.bilibili.com/x/web-interface/region/feed/rcmd?display_id=1&request_cnt=15&from_region=1003&device=web&plat=30',
        ),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data']?['archives'] != null) {
          final List<dynamic> archives = json['data']['archives'];
          final List<Music> recommended = [];

          for (var item in archives) {
            final albumName = item['tname'] ?? '未知专辑';

            recommended.add(
              Music(
                id: item['bvid'],
                title: item['title'],
                artist:
                    item['author']?['name'] ??
                    item['owner']?['name'] ??
                    '未知艺术家',
                album: albumName,
                coverUrl: (item['cover'] ?? '') + "@672w_378h",
                duration: null,
                audioUrl: '',
                pages: [],
              ),
            );
          }

          _recommendedList = recommended;
          _lastUpdated = DateTime.now();

          // 保存到缓存
          await _saveToCache();
        }
      }
    } catch (e) {
      debugPrint('获取推荐音乐失败: $e');
    }
  }

  /// 保存推荐列表到缓存
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataToSave = {
        'recommended': _recommendedList.map((m) => m.toJson()).toList(),
        'lastUpdated':
            _lastUpdated?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('recommendations_cache', jsonEncode(dataToSave));
    } catch (e) {
      debugPrint('保存推荐列表到缓存失败: $e');
    }
  }

  /// 保存猜你喜欢列表到缓存
  Future<void> _saveGuessToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataToSave = {
        'guessYouLike': _guessYouLikeList.map((m) => m.toJson()).toList(),
        'lastGuessUpdated':
            _lastGuessUpdated?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('guess_you_like_cache', jsonEncode(dataToSave));
    } catch (e) {
      debugPrint('保存猜你喜欢列表到缓存失败: $e');
    }
  }

  /// 从缓存加载数据
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载推荐列表
      final recommendationsCache = prefs.getString('recommendations_cache');
      if (recommendationsCache != null) {
        final data = jsonDecode(recommendationsCache);
        if (data['recommended'] != null) {
          _recommendedList = (data['recommended'] as List)
              .map((item) => Music.fromJson(item))
              .toList();
        }
        if (data['lastUpdated'] != null) {
          _lastUpdated = DateTime.fromMillisecondsSinceEpoch(
            data['lastUpdated'],
          );
        }
      }

      // 加载猜你喜欢列表
      final guessCache = prefs.getString('guess_you_like_cache');
      if (guessCache != null) {
        final data = jsonDecode(guessCache);
        if (data['guessYouLike'] != null) {
          _guessYouLikeList = (data['guessYouLike'] as List)
              .map((item) => Music.fromJson(item))
              .toList();
        }
        if (data['lastGuessUpdated'] != null) {
          _lastGuessUpdated = DateTime.fromMillisecondsSinceEpoch(
            data['lastGuessUpdated'],
          );
        }
      }
    } catch (e) {
      debugPrint('从缓存加载数据失败: $e');
    }
  }
}
