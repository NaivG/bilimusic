import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_results_overlay.dart';

/// 只数搜索次数，不碰网络。
class _CountingApiService extends ApiService {
  int searchCalls = 0;

  @override
  Future<SearchResponse> search(String query, {SearchResultType? type}) async {
    searchCalls++;
    return SearchResponse(
      keyword: query,
      results: [
        SearchResult(
          id: '36081646',
          title: '洛天依',
          subtitle: '198.3万粉丝 · 45投稿',
          coverUrl: '',
          type: SearchResultType.author,
          artist: const Artist(mid: 36081646, name: '洛天依'),
        ),
      ],
      hasMore: false,
      page: 1,
      totalResults: 1,
    );
  }
}

void main() {
  testWidgets('从分P歌单返回时搜索结果页不重新搜索', (tester) async {
    final api = _CountingApiService();
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      // 页面里的 UP 主入口会写这个单例，收尾把栈还原，别串到别的用例
      while (ShellPageManager.instance.canPop) {
        ShellPageManager.instance.pop();
      }
    });

    // 搜索页只发一次请求；结果页重建时应复用这份状态。
    await container.read(searchResultsProvider.notifier).search('洛天依');
    expect(api.searchCalls, 1);

    Widget buildPage() => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SearchResultsOverlay(query: '洛天依')),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(api.searchCalls, 1);
    expect(find.text('洛天依'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // 模拟点进分P歌单 / UP 主页：搜索页被销毁，返回时重建。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(api.searchCalls, 1, reason: '返回结果页只应重建视图，不应再发搜索请求');
    expect(find.text('洛天依'), findsOneWidget);
  });

  testWidgets('点击 UP 主结果进入歌手页', (tester) async {
    final api = _CountingApiService();
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      while (ShellPageManager.instance.canPop) {
        ShellPageManager.instance.pop();
      }
    });

    await container.read(searchResultsProvider.notifier).search('洛天依');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SearchResultsOverlay(query: '洛天依')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('洛天依'));
    await tester.pump();

    expect(ShellPageManager.instance.currentPage, ShellPage.artist);

    final up = ShellPageManager.instance.getArgs<UpProfile>('up');
    expect(up, isNotNull);
    expect(up!.mid, 36081646);
    expect(up.name, '洛天依');
  });
}
