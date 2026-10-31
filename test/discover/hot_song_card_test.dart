import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/features/discover/widgets/hot_song_card.dart';

HotSong _song() => HotSong.fromToplistJson({
  'rank': 1,
  'last_rank': 0,
  'music_id': 'MA1',
  'music_title': '与天齐',
  'singer': '指尖笑',
  'album': '与天齐',
  'heat': 1911128,
  'creation_bvid': 'BV1nnnp6SE4D',
  'creation_first_cid': 42960552319,
  'creation_duration': 62,
  'creation_title': '命途齐天但岁家',
  'creation_nickname': '骷髅Kuro',
  'creation_up': 38851875,
  'creation_play': 502170,
  'achievements': ['最高排名1'],
});

void main() {
  testWidgets('上半渲染歌曲行头，下半渲染相关视频', (tester) async {
    final song = _song();
    HotSong? played;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotSongCard(song: song, onTap: () => played = song),
        ),
      ),
    );

    // 歌曲行头
    expect(find.text('与天齐'), findsOneWidget);
    expect(find.text('指尖笑 - 与天齐'), findsOneWidget);
    expect(find.text('新'), findsOneWidget);
    expect(find.text('最高排名1'), findsOneWidget);
    expect(find.text('191.1万热度'), findsOneWidget);

    // 相关视频卡
    expect(find.text('命途齐天但岁家'), findsOneWidget);
    expect(find.text('骷髅Kuro · 50.2万播放'), findsOneWidget);
    expect(find.text('01:02'), findsOneWidget);

    // 整张卡片点哪儿都播相关视频
    await tester.tap(find.text('命途齐天但岁家'));
    expect(played, same(song));
  });

  testWidgets('不可播条目置灰，不渲染视频卡也不响应点击', (tester) async {
    final song = HotSong.fromToplistJson({
      'rank': 2,
      'music_title': '不可播热歌',
      'singer': '歌手B',
    });
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotSongCard(song: song, onTap: () => taps++),
        ),
      ),
    );

    expect(find.text('不可播热歌'), findsOneWidget);
    expect(find.text('相关视频'), findsNothing);

    await tester.tap(find.text('不可播热歌'));
    expect(taps, 0);
  });
}
