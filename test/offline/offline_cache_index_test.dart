import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/offline_track.dart';
import 'package:bilimusic/features/offline/logic/offline_cache_index.dart';
import 'package:bilimusic/features/offline/logic/offline_track_key.dart';

/// 离线命中判定：cid 缺失 / 分 P 回退 / bvid 兜底。
void main() {
  Music music({
    String id = 'BV1xx411c7mD',
    String cid = '',
    List<Page> pages = const [],
  }) => Music(
    id: id,
    cid: cid,
    title: '晴天',
    artist: const Artist(name: '周杰伦'),
    album: '叶惠美',
    coverUrl: '',
    audioUrl: '',
    pages: pages,
  );

  Page page(String cid) => Page(cid: cid, duration: '180', part: 'P1');

  OfflineTrack track({String bvid = 'BV1xx411c7mD', String cid = '12345'}) =>
      OfflineTrack(
        bvid: bvid,
        cid: cid,
        title: '晴天',
        artist: '周杰伦',
        filePath: '/tmp/$bvid-$cid.m4a',
        qualityId: '30280',
        fileSize: 128,
        downloadedAt: DateTime(2026, 1, 1),
      );

  group('offlineEffectiveCid', () {
    test('优先用 music.cid', () {
      expect(offlineEffectiveCid(music(cid: '12345')), '12345');
    });

    test('cid 缺失时退化到首分 P', () {
      expect(
        offlineEffectiveCid(music(pages: [page('111'), page('222')])),
        '111',
      );
    });

    test('两者都没有时为空串', () {
      expect(offlineEffectiveCid(music()), '');
    });
  });

  group('OfflineCacheIndex', () {
    test('精确 cid 命中', () {
      final index = OfflineCacheIndex([track()]);
      expect(index.contains(music(cid: '12345')), isTrue);
      expect(index.contains(music(cid: '54321')), isFalse);
    });

    test('cid 缺失的分 P 曲目按首分 P 命中', () {
      final index = OfflineCacheIndex([track(cid: '111')]);
      expect(index.contains(music(pages: [page('111'), page('222')])), isTrue);
      expect(index.contains(music(pages: [page('222'), page('111')])), isFalse);
    });

    test('cid 完全未知（稿件卡片）时按 bvid 兜底', () {
      final index = OfflineCacheIndex([track(cid: '真实cid')]);
      expect(index.contains(music()), isTrue);
      expect(index.contains(music(id: 'BV1yy411c7mE')), isFalse);
    });

    test('空索引不命中任何曲目', () {
      final index = OfflineCacheIndex(const []);
      expect(index.isEmpty, isTrue);
      expect(index.contains(music()), isFalse);
      expect(index.contains(music(cid: '12345')), isFalse);
    });
  });
}
