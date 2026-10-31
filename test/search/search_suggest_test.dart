import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/domain/search_suggest.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_suggest_panel.dart';

/// 顶掉 [ApiService] 默认的 `musicCacheManager`：它一构造就去问 path_provider。
class _StubMusicCache implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试不该触碰音频缓存：${invocation.memberName}');
}

/// 立即返回固定联想词，并记录被请求的关键词。
class _FakeApiService extends ApiService {
  _FakeApiService() : super(musicCache: _StubMusicCache());

  final List<String> terms = [];

  @override
  Future<List<SearchSuggest>> fetchSearchSuggest(String term) async {
    terms.add(term);
    return [SearchSuggest(value: term, name: term)];
  }
}

/// 手动控制每次联想请求的返回时机。
class _DeferredApiService extends ApiService {
  _DeferredApiService() : super(musicCache: _StubMusicCache());

  final Map<String, Completer<List<SearchSuggest>>> pending = {};

  @override
  Future<List<SearchSuggest>> fetchSearchSuggest(String term) {
    final completer = Completer<List<SearchSuggest>>();
    pending[term] = completer;
    return completer.future;
  }
}

void main() {
  group('ApiService.fetchSearchSuggest', () {
    test('走 s.search.bilibili.com 并解析 result.tag', () async {
      late Uri requested;
      final client = BiliClient(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 0,
                'result': {
                  'tag': [
                    {
                      'value': '周杰伦歌曲全集',
                      'term': '周杰伦歌曲全集',
                      'name': '<em class="suggest_high_light">周杰伦</em>歌曲全集',
                    },
                  ],
                },
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final api = ApiService(client: client, musicCache: _StubMusicCache());

      final items = await api.fetchSearchSuggest('周杰伦');

      expect(requested.host, 's.search.bilibili.com');
      expect(requested.path, '/main/suggest');
      expect(requested.queryParameters['term'], '周杰伦');
      expect(requested.queryParameters['main_ver'], 'v1');
      expect(requested.queryParameters.containsKey('highlight'), isTrue);
      expect(items.single.value, '周杰伦歌曲全集');
      expect(items.single.name, '周杰伦歌曲全集');
    });

    test('业务错误返回空列表', () async {
      final api = ApiService(
        client: BiliClient(
          httpClient: MockClient(
            (request) async => http.Response('{"code":-500}', 200),
          ),
        ),
        musicCache: _StubMusicCache(),
      );

      expect(await api.fetchSearchSuggest('周杰伦'), isEmpty);
    });
  });

  group('SearchSuggest 解析', () {
    test('剥掉高亮标签、还原实体并去重', () {
      final items = SearchSuggest.listFromResponse(const {
        'code': 0,
        'result': {
          'tag': [
            {
              'value': '周杰伦歌曲全集',
              'term': '周杰伦歌曲全集',
              'name': '<em class="suggest_high_light">周杰伦</em>歌曲全集',
            },
            {
              'value': 'A&B',
              'term': 'A&B',
              'name': '<em class="suggest_high_light">A</em>&amp;B',
            },
            {'value': '', 'term': '备用词', 'name': ''},
            {'value': 'bilibili://video/1', 'term': '', 'name': '视频'},
            {'value': 'A&B', 'term': 'A&B', 'name': '重复词'},
            '不是对象',
          ],
        },
      });

      expect(items.map((item) => item.value), ['周杰伦歌曲全集', 'A&B', '备用词']);
      expect(items.first.name, '周杰伦歌曲全集');
      expect(items[1].name, 'A&B');
      expect(items[2].name, '备用词');
    });

    test('result/tag 缺失或类型不对时返回空列表', () {
      expect(SearchSuggest.listFromResponse(const {}), isEmpty);
      expect(
        SearchSuggest.listFromResponse(const {
          'result': {'tag': 'not-a-list'},
        }),
        isEmpty,
      );
    });

    test('数字实体也可还原', () {
      expect(stripSuggestMarkup('&#20320;&#x597d;&nbsp;'), '你好 ');
    });
  });

  group('SearchSuggestNotifier', () {
    testWidgets('输入防抖后只请求最后一次关键词', (tester) async {
      final api = _FakeApiService();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchSuggestProvider.notifier);
      notifier.update('周');
      await tester.pump(const Duration(milliseconds: 100));
      notifier.update('周杰');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(api.terms, ['周杰']);
      final state = container.read(searchSuggestProvider);
      expect(state.term, '周杰');
      expect(state.isLoading, isFalse);
      expect(state.items.single.value, '周杰');
    });

    testWidgets('过期关键词的响应不会覆盖新结果', (tester) async {
      final api = _DeferredApiService();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchSuggestProvider.notifier);
      notifier.update('周');
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.pending.containsKey('周'), isTrue);

      notifier.update('周杰');
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.pending.containsKey('周杰'), isTrue);

      api.pending['周杰']!.complete(const [
        SearchSuggest(value: '周杰', name: '周杰'),
      ]);
      await tester.pump();
      expect(container.read(searchSuggestProvider).items.single.value, '周杰');

      api.pending['周']!.complete(const [SearchSuggest(value: '周', name: '周')]);
      await tester.pump();
      expect(container.read(searchSuggestProvider).items.single.value, '周杰');
    });
  });

  group('SearchSuggestPanel', () {
    testWidgets('空输入展示热门搜索，有输入展示联想列表', (tester) async {
      final api = _FakeApiService();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      String? selected;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SearchSuggestPanel(onSelected: (value) => selected = value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('热门搜索'), findsOneWidget);
      await tester.tap(find.text('周杰伦'));
      expect(selected, '周杰伦');

      container.read(searchSuggestProvider.notifier).update('周');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      expect(selected, '周');
    });
  });
}
