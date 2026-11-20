import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/offline_track.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_song_list.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 歌单曲目表多选：批量删除之外的「缓存」入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 封面缓存要写盘，测试里把 path_provider 指到临时目录。
  void stubPathProvider() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          Directory.systemTemp.createTempSync('bilimusic_song_list_cache').path,
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

  OfflineTrack offlineTrack(Music music, {String? cid}) => OfflineTrack(
    bvid: music.id,
    cid: cid ?? music.cid,
    title: music.title,
    artist: music.artist.name,
    filePath: '/tmp/${music.id}_${cid ?? music.cid}.m4a',
    qualityId: '30280',
    fileSize: 128,
    downloadedAt: DateTime(2026, 1, 1),
  );

  /// 建一棵只含曲目表的最小页面树；离线表用假 Notifier 顶上。
  Future<ProviderContainer> pumpList(
    WidgetTester tester,
    List<Music> songs, {
    bool isLandscape = false,
    Size viewport = const Size(412, 892),
    double textScale = 1,
    Future<bool> Function(List<Music>)? onRemoveMany,
    Future<void> Function(List<Music>)? onCacheMany,
    List<OfflineTrack> offlineTracks = const [],
    OfflineTracksNotifier Function()? notifierBuilder,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        offlineTracksProvider.overrideWith(
          notifierBuilder ?? () => _FakeOfflineTracksNotifier(offlineTracks),
        ),
      ],
    );
    addTearDown(container.dispose);
    // 预载离线表：已缓存标记在进入多选态时就能稳定出现。
    await container.read(offlineTracksProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeRegistry.defaultTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    PlaylistSongList(
                      // 每次 pump 都是全新状态，避免复用上一棵树的 _selectionMode。
                      key: UniqueKey(),
                      songs: songs,
                      isLandscape: isLandscape,
                      onSongTap: (_) {},
                      onRemoveMany: onRemoveMany,
                      onCacheMany: onCacheMany,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('只提供缓存回调也有多选入口，工具栏不出现删除', (tester) async {
    stubPathProvider();
    await pumpList(tester, List.generate(3, music), onCacheMany: (_) async {});

    expect(find.text('多选'), findsOneWidget);

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    expect(find.text('已选 0 首'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.textContaining('删除'), findsNothing);
  });

  testWidgets('没有任何批量回调时不显示多选入口', (tester) async {
    stubPathProvider();
    await pumpList(tester, List.generate(3, music));

    expect(find.text('多选'), findsNothing);
  });

  testWidgets('多选两首后点缓存：回调按曲目表顺序收到选中曲目', (tester) async {
    stubPathProvider();
    final songs = List.generate(4, music);
    List<Music>? received;
    await pumpList(
      tester,
      songs,
      onCacheMany: (selected) async => received = selected,
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    // 故意逆序点选，回调仍应按曲目表顺序给。
    await tester.tap(find.text('曲目 2'));
    await tester.pump();
    await tester.tap(find.text('曲目 0'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首'), findsOneWidget);

    await tester.tap(find.text('缓存'));
    await tester.pumpAndSettle();

    expect(received?.map((music) => music.title), ['曲目 0', '曲目 2']);
    // 缓存结束保留多选态：失败/跳过的曲目可以就地再试。
    expect(find.text('已选 2 首'), findsOneWidget);
  });

  testWidgets('缓存进行中禁用工具栏，重复点击不会重复触发', (tester) async {
    stubPathProvider();
    final gate = Completer<void>();
    var calls = 0;
    await pumpList(
      tester,
      List.generate(2, music),
      onCacheMany: (_) async {
        calls++;
        await gate.future;
      },
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('缓存'));
    await tester.pump();
    // 进行中再点一次：按钮已禁用，回调不会再进。
    await tester.tap(find.text('缓存'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('缓存回调抛错后工具栏恢复，可以再次尝试', (tester) async {
    stubPathProvider();
    var calls = 0;
    await pumpList(
      tester,
      List.generate(2, music),
      onCacheMany: (_) async {
        calls++;
        throw StateError('网络收音失败');
      },
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('缓存'));
    await tester.pumpAndSettle();
    // 异常由回调方提示，列表只负责把忙碌态收回来。
    expect(tester.takeException(), isNull);
    expect(calls, 1);

    await tester.tap(find.text('缓存'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('横屏（780×360）用完整标签工具栏且不溢出', (tester) async {
    stubPathProvider();
    await pumpList(
      tester,
      List.generate(4, music),
      isLandscape: true,
      viewport: const Size(780, 360),
      onRemoveMany: (_) async => true,
      onCacheMany: (_) async {},
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('已选 4 首'), findsOneWidget);
  });

  testWidgets('多选态给已缓存曲目加标记，退出多选后不显示', (tester) async {
    stubPathProvider();
    final songs = List.generate(3, music);
    await pumpList(
      tester,
      songs,
      onCacheMany: (_) async {},
      offlineTracks: [offlineTrack(songs[1])],
    );

    expect(find.byIcon(Icons.download_done_rounded), findsNothing);

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_done_rounded), findsNothing);
  });

  testWidgets('320 / 360 窄屏落成图标工具栏，计数仍完整可见', (tester) async {
    stubPathProvider();
    for (final width in <double>[320, 360]) {
      await pumpList(
        tester,
        List.generate(20, music),
        viewport: Size(width, 700),
        onRemoveMany: (_) async => true,
        onCacheMany: (_) async {},
      );

      await tester.tap(find.text('多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '${width}px 宽');
      // 紧凑模式没有文字按钮，但「已选 N 首」有足够宽度。
      expect(find.text('已选 20 首'), findsOneWidget, reason: '${width}px 宽');
      expect(find.text('缓存'), findsNothing, reason: '${width}px 宽');
      expect(find.text('删除'), findsNothing, reason: '${width}px 宽');
      expect(
        tester.getSize(find.text('已选 20 首')).width,
        greaterThan(60),
        reason: '${width}px 宽下计数不能被压没',
      );
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    }
  });

  testWidgets('412 宽默认字号用完整标签工具栏', (tester) async {
    stubPathProvider();
    await pumpList(
      tester,
      List.generate(20, music),
      onRemoveMany: (_) async => true,
      onCacheMany: (_) async {},
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('已选 20 首'), findsOneWidget);
  });

  testWidgets('大字号（1.3×）下窄屏/常规屏进入多选都不溢出，计数可见', (tester) async {
    stubPathProvider();
    for (final width in <double>[320, 412]) {
      await pumpList(
        tester,
        List.generate(20, music),
        viewport: Size(width, 700),
        textScale: 1.3,
        onRemoveMany: (_) async => true,
        onCacheMany: (_) async {},
      );

      await tester.tap(find.text('多选'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '${width}px @1.3×');
      expect(find.text('已选 0 首'), findsOneWidget, reason: '${width}px @1.3×');
      expect(
        tester.getSize(find.text('已选 0 首')).width,
        greaterThan(60),
        reason: '${width}px @1.3× 下计数不能被压没',
      );
    }
  });

  testWidgets('cid 缺失的稿件卡片按 bvid 命中已缓存标记', (tester) async {
    stubPathProvider();
    final card = music(0); // 推荐流卡片：cid 为空、无分 P
    final cardMusic = Music(
      id: card.id,
      title: card.title,
      artist: card.artist,
      album: card.album,
      coverUrl: '',
      audioUrl: '',
    );

    await pumpList(
      tester,
      [cardMusic],
      onCacheMany: (_) async {},
      // 落库时补到的真实 cid，与卡片上的空 cid 不同。
      offlineTracks: [offlineTrack(card, cid: '99999')],
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
  });

  testWidgets('缓存完成后离线表刷新，标记立即出现', (tester) async {
    stubPathProvider();
    final songs = List.generate(3, music);
    final fake = _MutableOfflineTracksNotifier();

    await pumpList(
      tester,
      songs,
      onCacheMany: (selected) async {
        fake.setTracks([offlineTrack(selected.first)]);
      },
      notifierBuilder: () => fake,
    );

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('曲目 0'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_done_rounded), findsNothing);

    await tester.tap(find.text('缓存'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
  });
}

class _FakeOfflineTracksNotifier extends OfflineTracksNotifier {
  _FakeOfflineTracksNotifier(this._tracks);

  final List<OfflineTrack> _tracks;

  @override
  Future<List<OfflineTrack>> build() async => _tracks;
}

/// 可在测试中改快照并触发重算的假离线表。
class _MutableOfflineTracksNotifier extends OfflineTracksNotifier {
  List<OfflineTrack> _tracks = const [];

  @override
  Future<List<OfflineTrack>> build() async => _tracks;

  void setTracks(List<OfflineTrack> tracks) {
    _tracks = tracks;
    ref.invalidateSelf();
  }
}
