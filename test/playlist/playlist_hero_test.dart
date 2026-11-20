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

  testWidgets('歌单头：封面是独立 Hero，竖屏 176 / 横屏 196', (tester) async {
    final playlist = Playlist(
      id: 'playlist_cover',
      name: '夜路耳机',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    Future<void> pumpHero({required bool isLandscape}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlaylistHero(playlist: playlist, isLandscape: isLandscape),
            ),
          ),
        ),
      );
    }

    await pumpHero(isLandscape: false);

    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'playlist_cover_playlist_cover');
    expect(tester.getSize(find.byType(Hero)), const Size(176, 176));
    expect(find.text('PLAYLIST'), findsOneWidget);
    expect(find.text('夜路耳机'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('随机播放'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);

    await pumpHero(isLandscape: true);

    expect(tester.getSize(find.byType(Hero)), const Size(196, 196));
  });
}
