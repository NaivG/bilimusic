import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/models/offline_track.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/offline/ui/offline_batch_download_dialog.dart';

void main() {
  Music sample(String id, String title) => Music(
    id: id,
    cid: 'cid_$id',
    title: title,
    artist: const Artist(name: '测试'),
    album: '',
    coverUrl: '',
    audioUrl: '',
  );

  testWidgets('批量缓存对话框展示进度并在完成后汇总结果', (tester) async {
    final fake = _FakeNotifier();
    final container = ProviderContainer(
      overrides: [offlineTracksProvider.overrideWith(() => fake)],
    );
    addTearDown(container.dispose);

    final songs = [sample('bv1', '晴天'), sample('bv2', '稻香')];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => OfflineBatchDownloadDialog(
                    songs: songs,
                    playlistName: '测试歌单',
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在离线缓存'), findsOneWidget);
    expect(find.text('测试歌单'), findsOneWidget);
    expect(find.text('正在缓存 2 / 2'), findsOneWidget);

    fake.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('离线缓存完成'), findsOneWidget);
    expect(find.text('新增 2 首 · 跳过 0 首'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });
}

class _FakeNotifier extends OfflineTracksNotifier {
  final gate = Completer<void>();

  @override
  Future<List<OfflineTrack>> build() async => const [];

  @override
  Future<OfflineBatchResult> downloadMany(
    List<Music> songs, {
    void Function(int current, int total, Music music)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    for (var i = 0; i < songs.length; i++) {
      onProgress?.call(i + 1, songs.length, songs[i]);
    }
    await gate.future;
    return OfflineBatchResult(downloaded: songs.length);
  }
}
