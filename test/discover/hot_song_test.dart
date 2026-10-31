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
        'creation_title': '「雨爱」唢呐版',
        'creation_nickname': '浑元Rysn',
        'creation_up': 42561463,
        'creation_play': 1566406,
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
      // 行头用榜单歌曲封面，视频卡用稿件封面
      expect(song.coverUrl, contains('music_metadata'));
      expect(song.isPlayable, isTrue);
      expect(song.relatedVideo?.bvid, 'BV1bJHN6nEo4');
      expect(song.relatedVideo?.title, '「雨爱」唢呐版');
      expect(song.relatedVideo?.uploaderName, '浑元Rysn');
      expect(song.relatedVideo?.uploaderMid, 42561463);
      expect(song.relatedVideo?.playCount, 1566406);
      expect(song.relatedVideo?.coverUrl, contains('archive'));
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

    test('没有相关视频时 isPlayable=false，播放入口据此置灰', () {
      final song = HotSong.fromToplistJson({'rank': 2, 'music_title': '歌'});
      expect(song.isPlayable, isFalse);
      expect(song.rankDelta, isNull);
      expect(song.relatedVideo, isNull);
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
    test('直接用相关视频的标题 / UP 主 / 封面构造曲目', () {
      final song = HotSong.fromToplistJson({
        'rank': 1,
        'music_title': '雨爱',
        'singer': '杨丞琳',
        'album': '思绪回到那年秋',
        'mv_cover': 'https://i0.hdslb.com/a.jpg',
        'creation_cover': 'http://i2.hdslb.com/bfs/archive/b.jpg',
        'creation_bvid': 'BV1bJHN6nEo4',
        'creation_first_cid': 43006886928,
        'creation_duration': 145,
        'creation_title': '「雨爱 (司凤版)」用唢呐吹完感觉老通透了',
        'creation_nickname': '浑元Rysn',
        'creation_up': 42561463,
        'creation_play': 1566406,
      });

      final music = song.toMusic();
      expect(music.id, 'BV1bJHN6nEo4');
      expect(music.cid, '43006886928');
      expect(music.title, '「雨爱 (司凤版)」用唢呐吹完感觉老通透了');
      expect(music.artist.name, '浑元Rysn');
      expect(music.artist.mid, 42561463);
      expect(music.duration, const Duration(seconds: 145));
      // 榜单歌曲的元数据不进入播放链路
      expect(music.title, isNot('雨爱'));
      expect(music.artist.name, isNot('杨丞琳'));
      expect(music.album, isEmpty);
      expect(music.coverUrl, contains('archive'));
      expect(music.subtitleText, '浑元Rysn');
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
      'creation_cover': 'http://i2.hdslb.com/bfs/archive/b.jpg',
      'heat': 870871,
      'creation_bvid': 'BV1As4y187Hq',
      'creation_first_cid': 1023506287,
      'creation_duration': 120,
      'creation_title': '“当恩怨各一半 我怎么圈揽”',
      'creation_nickname': '九三的耳朵不是特别好',
      'creation_up': 313580179,
      'creation_play': 6568671,
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
    expect(restored.relatedVideo?.title, '“当恩怨各一半 我怎么圈揽”');
    expect(restored.relatedVideo?.uploaderName, '九三的耳朵不是特别好');
    expect(restored.relatedVideo?.uploaderMid, 313580179);
    expect(restored.relatedVideo?.playCount, 6568671);
    expect(restored.relatedVideo?.coverUrl, contains('archive'));
    expect(restored.achievements, song.achievements);
  });

  test('缓存缺 relatedVideo 字段时仍保留可播放的 bvid', () {
    final restored = HotSong.fromJson({
      'rank': 1,
      'music_title': '新·与天齐',
      'singer': '指尖笑',
      'bvid': 'BV1nnnp6SE4D',
      'cid': '42960552319',
    });

    expect(restored.relatedVideo?.bvid, 'BV1nnnp6SE4D');
    expect(restored.toMusic().id, 'BV1nnnp6SE4D');
  });
}
