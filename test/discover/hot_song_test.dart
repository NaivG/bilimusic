import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/hot_song.dart';

void main() {
  group('HotSong.fromToplistJson', () {
    test('解析当期条目的全部展示字段', () {
      final song = HotSong.fromToplistJson({
        'rank': 3,
        'last_rank': 5,
        'music_id': 'MA640033680777043825',
        'music_title': '雨爱',
        'singer': '杨丞琳',
        'album': '思绪回到那年秋',
        'mv_cover': 'https://i0.hdslb.com/bfs/station_src/music_metadata/a.jpg',
        'creation_cover': 'http://i2.hdslb.com/bfs/archive/b.jpg',
        'heat': 1267339,
        'creation_bvid': 'BV1bJHN6nEo4',
        'creation_first_cid': 43006886928,
        'creation_duration': 145,
        'achievements': ['最高排名3'],
      });

      expect(song.rank, 3);
      expect(song.lastRank, 5);
      expect(song.title, '雨爱');
      expect(song.singer, '杨丞琳');
      expect(song.album, '思绪回到那年秋');
      expect(song.heat, 1267339);
      expect(song.bvid, 'BV1bJHN6nEo4');
      expect(song.cid, '43006886928');
      expect(song.durationSeconds, 145);
      expect(song.achievements, ['最高排名3']);
      // 官方歌曲封面优先于稿件封面
      expect(song.coverUrl, contains('music_metadata'));
      expect(song.isPlayable, isTrue);
    });

    test('官方封面缺失时回退稿件封面', () {
      final song = HotSong.fromToplistJson({
        'rank': 1,
        'music_title': '歌',
        'singer': '人',
        'mv_cover': '',
        'creation_cover': 'http://i2.hdslb.com/bfs/archive/b.jpg',
        'creation_bvid': 'BV1',
      });
      expect(song.coverUrl, contains('archive'));
    });

    test('没有创作稿件时 isPlayable=false，播放入口据此置灰', () {
      final song = HotSong.fromToplistJson({'rank': 2, 'music_title': '歌'});
      expect(song.isPlayable, isFalse);
      expect(song.rankDelta, isNull);
    });
  });

  group('HotSong.rankDelta', () {
    test('上期有排名时给出升降（正数 = 名次上升）', () {
      // 上期第 4、本期第 7：掉了 3 名
      expect(
        HotSong.fromToplistJson({'rank': 7, 'last_rank': 4}).rankDelta,
        -3,
      );
      // 上期第 7、本期第 4：涨了 3 名
      expect(HotSong.fromToplistJson({'rank': 4, 'last_rank': 7}).rankDelta, 3);
      expect(HotSong.fromToplistJson({'rank': 4, 'last_rank': 4}).rankDelta, 0);
    });

    test('last_rank=0 视为新上榜', () {
      expect(
        HotSong.fromToplistJson({'rank': 1, 'last_rank': 0}).rankDelta,
        isNull,
      );
    });
  });

  group('HotSong.toMusic', () {
    test('用歌手名当 artist，并带上稿件 bvid/cid 与时长', () {
      final song = HotSong.fromToplistJson({
        'rank': 1,
        'music_title': '雨爱',
        'singer': '杨丞琳',
        'album': '思绪回到那年秋',
        'mv_cover': 'https://i0.hdslb.com/a.jpg',
        'creation_bvid': 'BV1bJHN6nEo4',
        'creation_first_cid': 43006886928,
        'creation_duration': 145,
      });

      final music = song.toMusic();
      expect(music.id, 'BV1bJHN6nEo4');
      expect(music.cid, '43006886928');
      expect(music.title, '雨爱');
      expect(music.artist.name, '杨丞琳');
      expect(music.album, '思绪回到那年秋');
      expect(music.duration, const Duration(seconds: 145));
    });

    test('subtitleText 缺专辑时只显示歌手', () {
      final song = HotSong.fromToplistJson({
        'rank': 1,
        'music_title': '歌',
        'singer': '歌手',
      });
      expect(song.subtitleText, '歌手');
    });
  });

  test('toJson / fromJson 往返保持字段', () {
    final song = HotSong.fromToplistJson({
      'rank': 9,
      'last_rank': 12,
      'music_id': 'MA1',
      'music_title': '天龙八部之宿敌',
      'singer': '许嵩',
      'album': '天龙八部之宿敌',
      'mv_cover': 'https://i0.hdslb.com/a.jpg',
      'heat': 870871,
      'creation_bvid': 'BV1As4y187Hq',
      'creation_first_cid': 1023506287,
      'creation_duration': 120,
      'achievements': ['最高排名9'],
    });

    final restored = HotSong.fromJson(song.toJson());
    expect(restored.rank, song.rank);
    expect(restored.lastRank, song.lastRank);
    expect(restored.musicId, song.musicId);
    expect(restored.title, song.title);
    expect(restored.singer, song.singer);
    expect(restored.album, song.album);
    expect(restored.coverUrl, song.coverUrl);
    expect(restored.heat, song.heat);
    expect(restored.bvid, song.bvid);
    expect(restored.cid, song.cid);
    expect(restored.durationSeconds, song.durationSeconds);
    expect(restored.achievements, song.achievements);
  });
}
