import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/domain/search_suggest.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_entry_page.dart';

/// 顶掉 [ApiService] 默认的 `musicCacheManager`，测试里不碰 path_provider。
class _StubMusicCache implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试不该触碰音频缓存：${invocation.memberName}');
}

class _RecordingApiService extends ApiService {
  _RecordingApiService() : super(musicCache: _StubMusicCache());

  int searchCalls = 0;
  String? lastQuery;

  @override
  Future<SearchResponse> search(String query, {SearchResultType? type}) async {
    searchCalls++;
    lastQuery = query;
    return SearchResponse(
      keyword: query,
      results: const [],
      hasMore: false,
      page: 1,
      totalResults: 0,
    );
  }

  @override
  Future<List<SearchSuggest>> fetchSearchSuggest(String term) async => const [];
}

void main() {
  final pageManager = ShellPageManager.instance;

  void resetPageStack() {
    while (pageManager.canPop) {
      pageManager.pop();
    }
    pageManager.goToTab(0);
  }

  setUp(resetPageStack);
  tearDown(resetPageStack);

  testWidgets('竖屏搜索中间态提交后压入搜索结果页', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RecordingApiService();
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SearchEntryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '洛天依');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(api.searchCalls, 1);
    expect(api.lastQuery, '洛天依');
    expect(pageManager.currentPage, ShellPage.searchResults);
    expect(pageManager.getArgs<String>('query'), '洛天依');
    expect(container.read(searchSuggestProvider).term, '洛天依');
  });

  test('搜索中间态压栈时导航仍停在入口分区', () {
    pageManager.goToTab(1);
    pageManager.push(ShellPage.searchEntry);

    expect(pageManager.basePage, ShellPage.searchEntry);
    expect(pageManager.selectedTabIndex, 1);
  });
}
