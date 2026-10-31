import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/discover/discover_providers.dart';
import 'package:bilimusic/features/discover/logic/discover_cache.dart';

/// 占位音频缓存：本轮只测发现页的数据编排，不碰取流缓存。
/// `musicCacheManager` 一构造就去问 path_provider（测试环境没有插件）。
class _StubMusicCache implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试不该触碰音频缓存：${invocation.memberName}');
}

Music _music(String id) => Music(
  id: id,
  cid: '1',
  title: '曲目 $id',
  artist: const Artist(mid: 9, name: '某 UP'),
  album: '翻唱',
  coverUrl: '',
  duration: const Duration(seconds: 61),
  audioUrl: '',
);

HotSong _hotSong() => HotSong.fromToplistJson({
  'rank': 1,
  'music_title': '新·与天齐',
  'singer': '指尖笑',
  'creation_bvid': 'BV1nnnp6SE4D',
  'creation_first_cid': 42960552319,
});

/// 只统计调用次数、返回固定数据的 ApiService，不碰网络。
class _FakeApi extends ApiService {
  _FakeApi({
    this.hotSongs = const [],
    this.rankItems = const [],
    this.feedPages = const {},
  }) : super(musicCache: _StubMusicCache());

  final List<HotSong> hotSongs;
  final List<Music> rankItems;
  final Map<int, List<Music>> feedPages;

  int hotCalls = 0;
  int rankCalls = 0;
  final List<int> feedRequests = [];

  @override
  Future<({int listId, int period, DateTime? publishedAt, List<HotSong> songs})>
  fetchHotSongs({int listType = 1}) async {
    hotCalls++;
    return (
      listId: 445,
      period: 229,
      publishedAt: DateTime(2026, 10, 29),
      songs: hotSongs,
    );
  }

  @override
  Future<({String note, List<Music> items})> fetchMusicRanking({
    int limit = 30,
  }) async {
    rankCalls++;
    return (note: '榜单说明', items: rankItems);
  }

  @override
  Future<List<Music>> fetchMusicRegionFeed({
    int page = 1,
    int count = 20,
  }) async {
    feedRequests.add(page);
    return feedPages[page] ?? const [];
  }
}

ProviderContainer _container(_FakeApi api) {
  final container = ProviderContainer(
    overrides: [apiServiceProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('热歌榜', () {
    test('首次加载联网一次并落盘，再次 ensureLoaded 不再请求', () async {
      final api = _FakeApi(hotSongs: [_hotSong()]);
      final container = _container(api);

      await container.read(hotSongsProvider.notifier).ensureLoaded();
      expect(api.hotCalls, 1);
      final first = container.read(hotSongsProvider);
      expect(first.songs, hasLength(1));
      expect(first.period, 229);
      expect(first.fromCache, isFalse);

      await container.read(hotSongsProvider.notifier).ensureLoaded();
      expect(api.hotCalls, 1, reason: '数据还新鲜，不该重复拉');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(DiscoverCache.hotSongsKey),
        isNotNull,
        reason: '成功拿到数据后应写盘',
      );
      final cached = await DiscoverCache().readHotSongs();
      expect(cached, isNotNull);
      expect(cached!.songs, hasLength(1));
    });

    test('冷启动命中新鲜缓存时完全不联网', () async {
      final api = _FakeApi(hotSongs: [_hotSong()]);
      await DiscoverCache().writeHotSongs(
        HotSongsCache(
          songs: [_hotSong()],
          fetchedAt: DateTime.now(),
          listId: 445,
          period: 229,
        ),
      );

      final container = _container(api);
      await container.read(hotSongsProvider.notifier).ensureLoaded();

      expect(api.hotCalls, 0);
      final state = container.read(hotSongsProvider);
      expect(state.fromCache, isTrue);
      expect(state.songs, hasLength(1));
    });

    test('刷新在最小间隔内被节流，返回 false 且不增加请求', () async {
      final api = _FakeApi(hotSongs: [_hotSong()]);
      final container = _container(api);
      final notifier = container.read(hotSongsProvider.notifier);

      await notifier.ensureLoaded();
      expect(api.hotCalls, 1);

      expect(await notifier.refresh(), isFalse);
      expect(api.hotCalls, 1);
    });

    test('取不到数据时保留已有内容并给出错误提示', () async {
      final api = _FakeApi();
      final container = _container(api);
      await DiscoverCache().writeHotSongs(
        HotSongsCache(
          songs: [_hotSong()],
          // 过期缓存：会触发联网，但接口回空
          fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );

      await container.read(hotSongsProvider.notifier).ensureLoaded();
      final state = container.read(hotSongsProvider);
      expect(api.hotCalls, 1);
      expect(state.songs, hasLength(1), reason: '拉空不该把已有内容清掉');
      expect(state.errorMessage, isNotNull);
    });
  });

  group('音乐区排行', () {
    test('加载后用缓存，TTL 内不再请求', () async {
      final api = _FakeApi(rankItems: [_music('BV1')]);
      final container = _container(api);

      await container.read(musicRankProvider.notifier).ensureLoaded();
      expect(api.rankCalls, 1);
      expect(container.read(musicRankProvider).note, '榜单说明');

      // 换一个「新进程」的容器，只靠缓存
      final second = _container(api);
      await second.read(musicRankProvider.notifier).ensureLoaded();
      expect(api.rankCalls, 1);
      expect(second.read(musicRankProvider).fromCache, isTrue);
    });
  });

  group('发现流', () {
    test('换一批翻页，页码跟着走', () async {
      final api = _FakeApi(
        feedPages: {
          1: [_music('BV-feed-1')],
          2: [_music('BV-feed-2')],
        },
      );
      final container = _container(api);
      final notifier = container.read(discoverFeedProvider.notifier);

      await notifier.ensureLoaded();
      expect(container.read(discoverFeedProvider).page, 1);
      expect(container.read(discoverFeedProvider).items.single.id, 'BV-feed-1');

      await notifier.nextBatch();
      expect(container.read(discoverFeedProvider).page, 2);
      expect(container.read(discoverFeedProvider).items.single.id, 'BV-feed-2');
      expect(api.feedRequests, [1, 2]);
    });

    test('翻到头就回到第 1 页', () async {
      final api = _FakeApi(
        feedPages: {
          1: [_music('BV-feed-1')],
          2: [_music('BV-feed-2')],
          3: const [],
        },
      );
      final container = _container(api);
      final notifier = container.read(discoverFeedProvider.notifier);

      await notifier.ensureLoaded();
      await notifier.nextBatch();
      expect(container.read(discoverFeedProvider).page, 2);

      await notifier.nextBatch();
      // 第 3 页为空 → 回退第 1 页
      expect(api.feedRequests, [1, 2, 3, 1]);
      expect(container.read(discoverFeedProvider).page, 1);
      expect(container.read(discoverFeedProvider).items.single.id, 'BV-feed-1');
    });
  });
}
