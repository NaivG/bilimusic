import 'dart:convert';
import 'dart:io';

import 'package:bilimusic/core/network/av_bv.dart';
import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/domain/bili_item.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/search_result.dart';

/// CLI/TUI 宿主的网络装配层。
///
/// 复用 App 的 [NetworkConfig](UA/请求头/cookie 管理)与 [BiliClient]
/// (统一错误处理),但不触碰 Flutter 插件:cookie 不走
/// shared_preferences,而是直接读桌面 App 的存储文件 —— TUI 与 App
/// 共享登录态;音频流不走 flutter_cache_manager,直接返回远程 URL。
class TuiApi {
  TuiApi() : _client = BiliClient();

  final BiliClient _client;
  bool hasLoginCookies = false;

  /// 桌面 App 在 Windows 上的 shared_preferences 存储文件
  /// (路径由 path_provider_windows 按 Runner.rc 的公司/产品名推导)。
  static String get _prefsPath {
    final appData = Platform.environment['APPDATA'] ?? '';
    return '$appData\\github.naivg\\bilimusic\\shared_preferences.json';
  }

  Future<void> init() async {
    NetworkConfig.setBiliHeaders({
      'User-Agent': NetworkConfig.userAgent,
      'Referer': 'https://www.bilibili.com',
      'Access-Control-Allow-Origin': 'https://api.bilibili.com',
    });
    final cookies = _loadAppCookies();
    if (cookies.isNotEmpty) {
      // setCookies 内部的 prefs 持久化在 CLI 宿主里会静默跳过
      NetworkConfig.setCookies(cookies);
      hasLoginCookies = cookies.containsKey('SESSDATA');
    }
  }

  Map<String, String> _loadAppCookies() {
    try {
      final file = File(_prefsPath);
      if (!file.existsSync()) return const {};
      final root = jsonDecode(file.readAsStringSync());
      if (root is! Map) return const {};
      final raw = root['flutter.cookies'];
      if (raw is! String || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return const {};
    }
  }

  /// 关键词搜索(取 all/v2 中的 video 分组),支持 BV/AV 直达。
  /// 返回 (视频结果, 当前页, 总页数)。
  Future<(List<SearchResult>, int, int)> search(
    String keyword, {
    int page = 1,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.startsWith('BV1')) {
      return ([await _byBvid(trimmed)], 1, 1);
    }
    if (trimmed.toUpperCase().startsWith('AV')) {
      final digits = trimmed.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
      final aid = int.tryParse(digits);
      if (aid != null) return ([await _byBvid(av2bv(aid))], 1, 1);
      return (const <SearchResult>[], 1, 1);
    }

    final data = await _client.get(
      '/x/web-interface/search/all/v2',
      query: {'keyword': trimmed, 'page': '$page'},
    );
    final List<SearchResult> videos = [];
    if (data is Map<String, dynamic>) {
      final groups = data['result'] is List ? data['result'] as List : const [];
      for (final group in groups) {
        if (group is! Map || group['result_type'] != 'video') continue;
        final items = group['data'] is List ? group['data'] as List : const [];
        for (final item in items) {
          if (item is Map) {
            videos.add(
              SearchResult.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
                SearchResultType.video,
              ),
            );
          }
        }
      }
      final cur = data['page'] is int ? data['page'] as int : page;
      final numPages = data['numPages'] is int ? data['numPages'] as int : 1;
      return (videos, cur, numPages);
    }
    return (videos, page, 1);
  }

  Future<SearchResult> _byBvid(String bvid) async {
    final data = await _client.get(
      '/x/web-interface/view',
      query: {'bvid': bvid},
    );
    final item = BiliItem.fromViewApi(data as Map<String, dynamic>);
    final cover = item.pic;
    return SearchResult(
      id: bvid,
      title: item.title,
      subtitle: item.owner.name,
      coverUrl: cover.isNotEmpty ? '$cover$biliCoverThumbSuffix' : cover,
      type: SearchResultType.video,
    );
  }

  /// 官方推荐(音乐分区 rcmd),与桌面 App 的 RecommendationManager
  /// 使用同一端点。返回 (视频结果, 当前页, 总页数) 之外的推荐列表。
  ///
  /// 该端点直接返回 cid/duration/author/stat.view:
  /// 顺势把 cid 塞进 [SearchResult.pages],播放时免掉一次 view API 补全。
  Future<List<SearchResult>> recommendations() async {
    final data = await _client.get(
      '/x/web-interface/region/feed/rcmd',
      query: {
        'display_id': '1',
        'request_cnt': '15',
        'from_region': '1003',
        'device': 'web',
        'plat': '30',
      },
    );
    final archives = (data as Map<String, dynamic>?)?['archives'];
    if (archives is! List) return const [];
    final out = <SearchResult>[];
    for (final raw in archives) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      final author = json['author'] is Map ? json['author'] as Map : const {};
      final stat = json['stat'] is Map ? json['stat'] as Map : const {};
      final title = json['title']?.toString() ?? '';
      out.add(
        SearchResult(
          id: json['bvid']?.toString() ?? '',
          title: title,
          subtitle:
              '${author['name'] ?? '未知艺术家'} - 音乐 · ${_fmtCount(stat['view'])} 播放',
          coverUrl: json['cover']?.toString() ?? '',
          type: SearchResultType.video,
          pages: [
            Page(
              cid: json['cid']?.toString() ?? '',
              duration: json['duration']?.toString() ?? '0',
              part: title,
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// 解析可播放的音频流:cid 缺失时补 view API → playurl(DASH)。
  /// 与 ApiService.getAudioUrl 的差异:不落盘缓存,直接返回远程 URL。
  Future<Music> resolveAudio(SearchResult result) =>
      _ensureAudio(result.toMusic());

  Future<Music> _ensureAudio(Music music) async {
    var m = music;
    if (m.cid.isEmpty) {
      final data = await _client.get(
        '/x/web-interface/view',
        query: {'bvid': m.id},
      );
      final item = BiliItem.fromViewApi(data as Map<String, dynamic>);
      if (item.pages.isEmpty) {
        throw Exception('该视频无可用分P');
      }
      m = item.pages.first;
    }

    final data = await _client.get(
      '/x/player/playurl',
      query: {'bvid': m.id, 'cid': m.cid, 'fnval': '16'},
    );
    final dash = (data as Map<String, dynamic>?)?['dash'];
    final audios = dash is Map ? dash['audio'] as List? : null;
    if (audios == null || audios.isEmpty) {
      throw Exception('playurl 未返回 DASH 音频');
    }
    final url = audios.first['baseUrl']?.toString() ?? '';
    if (url.isEmpty) {
      throw Exception('音频 URL 为空');
    }
    return m.copyWith(audioUrl: url);
  }

  static String _fmtCount(Object? count) {
    final n = count is num
        ? count.toDouble()
        : double.tryParse('$count') ?? 0;
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toStringAsFixed(0);
  }

  void close() => _client.close();
}
