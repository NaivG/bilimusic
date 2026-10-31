import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/cookie_jar.dart';

/// 占位音频缓存：这几个接口都不碰缓存，它只是顶掉 [ApiService] 的默认值
/// ——`musicCacheManager` 一构造就去问 path_provider（纯 Dart 测试里没有 binding）。
class _StubMusicCache implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试不该触碰音频缓存：${invocation.memberName}');
}

ApiService _api(BiliClient client) =>
    ApiService(client: client, musicCache: _StubMusicCache());

/// 按路径分发的假网络：只认本文件注册的端点。
BiliClient _client(Map<String, Object?> routes) {
  return BiliClient(
    cookieJar: CookieJar(),
    httpClient: MockClient((request) async {
      final body = routes[request.url.path];
      if (body == null) {
        return http.Response('{"code":-404,"message":"not mocked"}', 404);
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

Map<String, Object?> _ok(Object? data) => {
  'code': 0,
  'message': '0',
  'data': data,
};

Map<String, Object?> _rankingItem(
  String bvid, {
  String cid = '100',
  String tname = '翻唱',
}) => {
  'bvid': bvid,
  'aid': 1,
  'cid': int.tryParse(cid) ?? cid,
  'tid': 31,
  'tname': tname,
  'title': '$tname 作品',
  'pic': 'https://i0.hdslb.com/bfs/archive/$bvid.jpg',
  'duration': 123,
  'owner': {'mid': 9, 'name': '某 UP', 'face': ''},
};

final _feedItem = {
  'aid': 1,
  'bvid': 'BV1feed',
  'cid': 777,
  'title': '推荐流作品',
  'cover': 'http://i0.hdslb.com/bfs/archive/feed.jpg',
  'duration': 201,
  'stat': {'view': 100, 'like': 10, 'danmaku': 1},
  'author': {'mid': 36081646, 'name': '洛天依'},
};

final _hotSong = {
  'rank': 1,
  'last_rank': 3,
  'music_id': 'MA1',
  'music_title': '新·与天齐',
  'singer': '指尖笑',
  'album': '与天齐',
  'mv_cover': 'https://i0.hdslb.com/bfs/station_src/music_metadata/a.jpg',
  'heat': 1911128,
  'creation_bvid': 'BV1nnnp6SE4D',
  'creation_first_cid': 42960552319,
  'creation_duration': 62,
  'achievements': ['最高排名1'],
};

Map<String, Object?> _hotRoutes() => {
  '/x/copyright-music-publicity/toplist/all_period': _ok({
    'list': {
      '2025': [
        {'ID': 443, 'priod': 228, 'publish_time': 1792750525},
      ],
      '2026': [
        {'ID': 443, 'priod': 228, 'publish_time': 1792750525},
        {'ID': 445, 'priod': 229, 'publish_time': 1793354401},
      ],
    },
  }),
  '/x/copyright-music-publicity/toplist/music_list': _ok({
    'list': [
      {..._hotSong, 'rank': 2, 'music_title': '第二名'},
      _hotSong,
    ],
    'list_id': 445,
  }),
};

void main() {
  group('fetchMusicRanking', () {
    test('稿件字段映射为 Music：带 cid、分区名当 album', () async {
      final api = _api(
        _client({
          '/x/web-interface/ranking/v2': _ok({
            'note': '根据稿件内容质量、近期的数据综合展示，动态更新',
            'list': [_rankingItem('BV1rank')],
          }),
        }),
      );

      final result = await api.fetchMusicRanking();

      expect(result.note, contains('根据稿件内容质量'));
      expect(result.items, hasLength(1));
      final music = result.items.single;
      expect(music.id, 'BV1rank');
      // 榜单条目自带 cid，点开即可直接取流
      expect(music.cid, '100');
      expect(music.album, '翻唱');
      expect(music.artist.mid, 9);
      expect(music.duration, const Duration(seconds: 123));
    });

    test('limit 截断整榜，空 bvid 的条目被丢弃', () async {
      final api = _api(
        _client({
          '/x/web-interface/ranking/v2': _ok({
            'list': [
              _rankingItem('BV1'),
              _rankingItem('BV2'),
              _rankingItem('BV3'),
              {'title': '没有 bvid 的坏条目'},
            ],
          }),
        }),
      );

      final result = await api.fetchMusicRanking(limit: 2);
      expect(result.items.map((m) => m.id), ['BV1', 'BV2']);
    });

    test('接口报错时返回空列表而不是抛异常', () async {
      final api = _api(
        _client({
          '/x/web-interface/ranking/v2': {'code': -352, 'message': '风控'},
        }),
      );

      final result = await api.fetchMusicRanking();
      expect(result.items, isEmpty);
      expect(result.note, isEmpty);
    });
  });

  group('fetchMusicRegionFeed', () {
    test('推荐流字段映射：cover/author/cid 都能认', () async {
      final api = _api(
        _client({
          '/x/web-interface/region/feed/rcmd': _ok({
            'archives': [_feedItem],
          }),
        }),
      );

      final items = await api.fetchMusicRegionFeed();
      expect(items, hasLength(1));
      final music = items.single;
      expect(music.id, 'BV1feed');
      expect(music.cid, '777');
      expect(music.duration, const Duration(seconds: 201));
      // 该端点用 author{mid,name}，mid 要能取到（歌手页入口依赖它）
      expect(music.artist.name, '洛天依');
      expect(music.artist.mid, 36081646);
    });

    test('62013 视为「该页没有内容」，返回空列表', () async {
      final api = _api(
        _client({
          '/x/web-interface/region/feed/rcmd': {
            'code': 62013,
            'message': '暂无更多内容',
            'data': null,
          },
        }),
      );

      expect(await api.fetchMusicRegionFeed(page: 4), isEmpty);
    });
  });

  group('fetchHotSongs', () {
    test('取发布时间最新的一期，并按名次排序', () async {
      final api = _api(_client(_hotRoutes()));

      final result = await api.fetchHotSongs();
      expect(result.listId, 445);
      expect(result.period, 229);
      expect(
        result.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1793354401 * 1000),
      );
      expect(result.songs.map((s) => s.rank), [1, 2]);
      expect(result.songs.first.title, '新·与天齐');
      expect(result.songs.first.isPlayable, isTrue);
    });

    test('期数表为空时返回空结果，不发第二个请求', () async {
      var musicListCalls = 0;
      final client = BiliClient(
        cookieJar: CookieJar(),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('music_list')) musicListCalls++;
          return http.Response.bytes(
            utf8.encode(jsonEncode(_ok({'list': <String, Object?>{}}))),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await _api(client).fetchHotSongs();
      expect(result.songs, isEmpty);
      expect(result.listId, 0);
      expect(musicListCalls, 0);
    });
  });
}
