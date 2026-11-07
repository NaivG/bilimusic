import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_hero.dart';

void main() {
  testWidgets('歌单更多菜单包含「离线缓存全部」并触发回调', (tester) async {
    var triggered = false;
    final music = Music(
      id: 'BV1xx411c7mD',
      cid: '12345',
      title: '晴天',
      artist: const Artist(name: '周杰伦'),
      album: '',
      coverUrl: '',
      audioUrl: '',
    );
    final playlist = Playlist(
      id: 'playlist_1',
      name: '测试歌单',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlaylistHero(
              playlist: playlist,
              songs: [music],
              isLandscape: false,
              onOfflineCacheAll: () => triggered = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.text('离线缓存全部'), findsOneWidget);

    await tester.tap(find.text('离线缓存全部'));
    await tester.pumpAndSettle();

    expect(triggered, isTrue);
  });
}
