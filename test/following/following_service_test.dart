import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/domain/bili_following.dart';
import 'package:bilimusic/features/following/following_service.dart';

/// 「查看关注」的编排层测试。
void main() {
  late _StubBiliClient client;
  late FollowingService service;

  setUp(() {
    client = _StubBiliClient();
    service = FollowingService(
      api: ApiService(client: client, musicCache: _StubMusicCache()),
    );
  });

  group('fetchFollowingsPage', () {
    test('解析 list 与 total，默认按关注顺序（不带 order_type）', () async {
      client.responder = (path, query) => {
        'list': [
          {'mid': 1, 'uname': 'A'},
          {'mid': '2', 'uname': 'B'},
        ],
        'total': 137,
      };

      final page1 = await service.fetchFollowingsPage(vmid: 42);

      expect(page1.total, 137);
      expect(page1.items.map((u) => u.mid), [1, 2]);
      expect(page1.items.map((u) => u.name), ['A', 'B']);

      final request = client.requests.single;
      expect(request.path, '/x/relation/followings');
      expect(request.query['vmid'], '42');
      expect(request.query['pn'], '1');
      expect(request.query['ps'], '${FollowingService.followingPageSize}');
      expect(request.query.containsKey('order_type'), isFalse);
      expect(request.signed, isFalse);
    });

    test('page / byAttention 透传到 query', () async {
      client.responder = (path, query) => {'list': [], 'total': 0};

      await service.fetchFollowingsPage(vmid: 42, page: 3, byAttention: true);

      final request = client.requests.single;
      expect(request.query['pn'], '3');
      expect(request.query['order_type'], 'attention');
    });

    test('接口失败时返回空页 + total 0，不抛给页面', () async {
      client.failure = const BiliApiException(-412, '请求被拦截');

      final page = await service.fetchFollowingsPage(vmid: 42);

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });
  });

  group('collectUserSongs', () {
    test('拉到上限（90 首）就停，album 用「UP主名 的投稿」', () async {
      // 每页满 30 首且还有下一页，服务必须自己在上限处收手
      client.responder = (path, query) =>
          _spaceVideos(query, pageSize: 30, total: 218);

      final songs = await service.collectUserSongs(_up(1234, '某UP'));

      expect(songs, hasLength(FollowingService.maxSongs));
      expect(client.requests, hasLength(3), reason: '90 首 = 3 页，多一页都不该要');
      expect(songs.first.album, '某UP 的投稿');
      expect(songs.first.id, 'BV1');
      for (final request in client.requests) {
        expect(request.path, '/x/space/wbi/arc/search');
        expect(request.signed, isTrue, reason: '投稿接口要 WBI 签名');
        expect(request.query['pn'], isNotNull);
        expect(request.query['order'], 'pubdate');
        expect(request.query['mid'], '1234');
      }
    });

    test('不满一页即到底，不再多要一页', () async {
      client.responder = (path, query) =>
          _spaceVideos(query, pageSize: 30, total: 12, fixedCount: 12);

      final songs = await service.collectUserSongs(_up(1234, '某UP'));

      expect(songs, hasLength(12));
      expect(client.requests, hasLength(1));
    });

    test('中间某页失败时返回已经拿到的部分', () async {
      client.responder = (path, query) {
        if (query['pn'] == '2') {
          throw const BiliApiException(-412, '请求被拦截');
        }
        return _spaceVideos(query, pageSize: 30, total: 218);
      };

      final songs = await service.collectUserSongs(_up(1234, '某UP'));

      expect(songs, hasLength(30), reason: '第二页失败，第一页的 30 首该留下');
      expect(client.requests, hasLength(2));
    });

    test('进度回调回传「已拿到 / 总数」', () async {
      client.responder = (path, query) =>
          _spaceVideos(query, pageSize: 30, total: 218);
      final progress = <(int, int)>[];

      await service.collectUserSongs(
        _up(1234, '某UP'),
        onProgress: (loaded, total) => progress.add((loaded, total)),
      );

      expect(progress, [(30, 218), (60, 218), (90, 218)]);
    });
  });
}

BiliFollowing _up(int mid, String name) => BiliFollowing(mid: mid, name: name);

/// 造一页投稿响应；[fixedCount] 给定后不再按 [pageSize] 铺满。
Map<String, dynamic> _spaceVideos(
  Map<String, Object?> query, {
  required int pageSize,
  required int total,
  int? fixedCount,
}) {
  final count = fixedCount ?? pageSize;
  final pn = int.tryParse('${query['pn']}') ?? 1;
  return {
    'list': {
      'vlist': [
        for (var i = 0; i < count; i++)
          {
            'bvid': 'BV${(pn - 1) * pageSize + i + 1}',
            'title': '第 ${(pn - 1) * pageSize + i + 1} 首',
            'author': '某UP',
            'length': '03:21',
            'pic': 'http://i0.hdslb.com/bfs/archive/x.jpg',
          },
      ],
    },
    'page': {'count': total, 'pn': pn, 'ps': pageSize},
  };
}

class _RecordedRequest {
  _RecordedRequest(this.path, this.query, this.signed);

  final String path;
  final Map<String, Object?> query;
  final bool signed;
}

/// 桩客户端：记录每次请求，按 [responder] 回 `data` 字段（或按 [failure] 抛错）。
class _StubBiliClient extends BiliClient {
  final List<_RecordedRequest> requests = [];

  Map<String, dynamic> Function(String path, Map<String, Object?> query)?
  responder;

  /// 非空时所有请求都失败，模拟接口报错 / 风控。
  BiliException? failure;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, Object?>? query,
    bool signed = false,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
  }) async {
    final effectiveQuery = query ?? const <String, Object?>{};
    requests.add(_RecordedRequest(path, effectiveQuery, signed));

    final error = failure;
    if (error != null) throw error;

    final handler = responder;
    if (handler == null) throw UnimplementedError('测试未覆盖的接口：$path');
    return handler(path, effectiveQuery);
  }
}

/// 占位音频缓存：这条链路根本不碰缓存，它只是顶掉 [ApiService] 的默认值
/// ——`musicCacheManager` 一构造就去问 path_provider（纯 Dart 测试里没有 binding）。
class _StubMusicCache implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试不该触碰音频缓存：${invocation.memberName}');
}
