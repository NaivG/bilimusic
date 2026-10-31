import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/discover/logic/discover_cache.dart';
import 'package:bilimusic/features/discover/ui/discover_page.dart';

/// 封面缓存要写盘，测试里把 path_provider 指到临时目录。
void _stubPathProvider() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('bilimusic_test').path,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    ),
  );
}

Music _music(String id, String title) => Music(
  id: id,
  cid: '1',
  title: title,
  artist: const Artist(mid: 9, name: '某 UP'),
  album: '翻唱',
  coverUrl: '',
  duration: const Duration(seconds: 61),
  audioUrl: '',
);

HotSong _hotSong(String title, int rank) => HotSong.fromToplistJson({
  'rank': rank,
  'last_rank': rank + 1,
  'music_title': title,
  'singer': '歌手A',
  'album': '专辑A',
  'heat': 12345,
  'creation_bvid': 'BV-$title',
  'creation_first_cid': 1,
  'creation_duration': 120,
  'creation_title': '视频-$title',
  'creation_nickname': 'UP-$title',
  'creation_up': 42,
  'creation_play': 502170,
});

/// 用新鲜缓存把三个分区喂满：页面打开不联网，只验证渲染。
Future<void> _seedCache() async {
  SharedPreferences.setMockInitialValues({});
  final cache = DiscoverCache();
  final now = DateTime.now();
  await cache.writeHotSongs(
    HotSongsCache(
      songs: [_hotSong('热歌一', 1), _hotSong('热歌二', 2)],
      fetchedAt: now,
      listId: 445,
      period: 229,
      publishedAt: DateTime(2026, 10, 29),
    ),
  );
  await cache.writeMusicRank(
    MusicRankCache(
      items: [_music('BVrank1', '排行一'), _music('BVrank2', '排行二')],
      fetchedAt: now,
      note: '根据稿件内容质量动态更新',
    ),
  );
  await cache.writeMusicFeed(
    MusicFeedCache(items: [_music('BVfeed1', '推荐一')], fetchedAt: now, page: 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('发现页渲染三个分区，并展示缓存内容', (tester) async {
    _stubPathProvider();
    await _seedCache();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DiscoverPage())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('热歌榜'), findsOneWidget);
    expect(find.text('音乐区排行'), findsOneWidget);
    expect(find.text('发现音乐'), findsOneWidget);

    // 缓存内容直接可见，并标注了期数与缓存状态
    expect(find.text('热歌一'), findsOneWidget);
    expect(find.textContaining('第 229 期'), findsOneWidget);
    expect(find.text('排行一'), findsOneWidget);
    expect(find.text('推荐一'), findsOneWidget);

    // 热歌行是上下两段：歌曲行头 + 相关视频卡
    expect(find.text('视频-热歌一'), findsOneWidget);
    expect(find.textContaining('50.2万播放'), findsNWidgets(2));

    // 榜单尾部：两个条目都带热度与名次变化
    expect(find.textContaining('万热度'), findsNWidgets(2));

    // 可播的曲目行都挂上了右键 / 长按菜单（热歌 2 + 排行 2 + 推荐 1）
    expect(find.byType(ContextMenuWidget), findsNWidgets(5));
  });

  testWidgets('没有可用稿件的热歌行不挂右键菜单', (tester) async {
    _stubPathProvider();
    SharedPreferences.setMockInitialValues({});
    final cache = DiscoverCache();
    final now = DateTime.now();
    await cache.writeHotSongs(
      HotSongsCache(
        songs: [
          HotSong.fromToplistJson({
            'rank': 1,
            'last_rank': 0,
            'music_title': '不可播热歌',
            'singer': '歌手B',
            'heat': 100,
            'creation_bvid': '',
          }),
          _hotSong('可播热歌', 2),
        ],
        fetchedAt: now,
        listId: 445,
        period: 230,
        publishedAt: DateTime(2026, 10, 30),
      ),
    );
    await cache.writeMusicRank(
      MusicRankCache(items: [_music('BVrank1', '排行一')], fetchedAt: now),
    );
    await cache.writeMusicFeed(
      MusicFeedCache(
        items: [_music('BVfeed1', '推荐一')],
        fetchedAt: now,
        page: 1,
      ),
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DiscoverPage())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('不可播热歌'), findsOneWidget);
    // 不可播的热歌行不接管菜单，其余三行（可播热歌 / 排行 / 推荐）各一个。
    expect(find.byType(ContextMenuWidget), findsNWidgets(3));
  });

  testWidgets('窄屏（手机竖屏）下不溢出', (tester) async {
    _stubPathProvider();
    await _seedCache();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DiscoverPage())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('热歌榜'), findsOneWidget);
  });
}
