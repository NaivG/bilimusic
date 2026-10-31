import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';

void main() {
  Music music(String id, String cid) => Music(
    id: id,
    cid: cid,
    title: id,
    artist: const Artist(name: 'artist'),
    album: 'album',
    coverUrl: '',
    audioUrl: '',
  );

  group('Music.subtitleText', () {
    test('有专辑时显示「艺术家 - 专辑」', () {
      expect(music('BV1', '1').subtitleText, 'artist - album');
    });

    test('没有专辑时只显示艺术家', () {
      final track = Music(
        id: 'BV1',
        title: '视频',
        artist: const Artist(name: 'UP 主'),
        album: '',
        coverUrl: '',
        audioUrl: '',
      );
      expect(track.subtitleText, 'UP 主');
    });
  });

  group('Music.sameTrackAs', () {
    test('空 cid 视为通配：先入列后回填 cid 仍算同一首', () {
      final pending = music('BV1', '');
      final detailed = music('BV1', '123');

      expect(pending.sameTrackAs(detailed), isTrue);
      expect(detailed.sameTrackAs(pending), isTrue);
    });

    test('同 bvid 的不同分P不是同一首', () {
      expect(music('BV1', '1').sameTrackAs(music('BV1', '2')), isFalse);
    });

    test('不同 bvid 不是同一首', () {
      expect(music('BV1', '').sameTrackAs(music('BV2', '')), isFalse);
    });

    test('相同 (bvid, cid) 是同一首', () {
      expect(music('BV1', '123').sameTrackAs(music('BV1', '123')), isTrue);
    });
  });
}
