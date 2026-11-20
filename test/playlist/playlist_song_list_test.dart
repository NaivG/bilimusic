import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_song_list.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 歌单曲目表：整份数据一次性进内存，行按滚动视口懒构建。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 封面缓存要写盘，测试里把 path_provider 指到临时目录。
  void stubPathProvider() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          Directory.systemTemp.createTempSync('bilimusic_song_list_test').path,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      ),
    );
  }

  Music music(int index) => Music(
    id: 'BV1xx411c7m${index.toString().padLeft(2, '0')}',
    cid: '${1000 + index}',
    title: '曲目 $index',
    artist: const Artist(mid: 9, name: '测试歌手'),
    album: '测试专辑',
    coverUrl: '',
    duration: const Duration(seconds: 180),
    audioUrl: '',
  );

  Future<void> pumpList(
    WidgetTester tester,
    List<Music> songs, {
    bool isLandscape = false,
    Size? viewport,
  }) async {
    if (viewport != null) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeRegistry.defaultTheme.light(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PlaylistSongList(
                  songs: songs,
                  isLandscape: isLandscape,
                  onSongTap: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长歌单不折叠：无「查看全部」入口，首帧只构建视口内的行', (tester) async {
    stubPathProvider();
    final songs = List<Music>.generate(120, music);

    await pumpList(tester, songs);
    expect(tester.takeException(), isNull);

    // 表头统计的是全量数据。
    expect(find.text('曲目'), findsOneWidget);
    expect(find.textContaining('120 首'), findsOneWidget);
    // 折叠入口已移除。
    expect(find.textContaining('查看全部'), findsNothing);

    // 懒构建：120 首只构建视口 + 缓存区里的十几行。
    final built = tester.widgetList(find.byType(PlaylistTrackRow)).length;
    expect(built, greaterThan(0));
    expect(built, lessThan(40));
  });

  testWidgets('滚动到底能看到最后一首：全量条目都在列表里', (tester) async {
    stubPathProvider();
    final songs = List<Music>.generate(60, music);

    await pumpList(tester, songs);
    expect(find.text('曲目 59'), findsNothing);

    await tester.scrollUntilVisible(find.text('曲目 59'), 400);
    expect(find.text('曲目 59'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('竖屏 / 横屏 / 方屏都不溢出', (tester) async {
    stubPathProvider();
    final songs = List<Music>.generate(40, music);

    final cases = <({String name, bool isLandscape, Size viewport})>[
      (name: '手机竖屏', isLandscape: false, viewport: const Size(412, 892)),
      (name: '手机横屏', isLandscape: true, viewport: const Size(780, 360)),
      (name: '方屏', isLandscape: false, viewport: const Size(800, 800)),
    ];

    for (final testCase in cases) {
      await pumpList(
        tester,
        songs,
        isLandscape: testCase.isLandscape,
        viewport: testCase.viewport,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '${testCase.name}（${testCase.viewport}）下曲目表不应溢出',
      );
      expect(find.text('曲目 1'), findsOneWidget, reason: testCase.name);
    }
  });
}
