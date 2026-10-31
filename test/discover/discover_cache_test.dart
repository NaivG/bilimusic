import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/discover/logic/discover_cache.dart';

Music _music(String id) => Music(
  id: id,
  cid: '1',
  title: '曲目 $id',
  artist: const Artist(mid: 9, name: '某 UP'),
  album: '翻唱',
  coverUrl: 'https://i0.hdslb.com/a.jpg',
  duration: const Duration(seconds: 61),
  audioUrl: '',
);

HotSong _hotSong() => HotSong.fromToplistJson({
  'rank': 1,
  'last_rank': 3,
  'music_id': 'MA1',
  'music_title': '新·与天齐',
  'singer': '指尖笑',
  'album': '与天齐',
  'mv_cover': 'https://i0.hdslb.com/a.jpg',
  'heat': 1911128,
  'creation_bvid': 'BV1nnnp6SE4D',
  'creation_first_cid': 42960552319,
  'creation_duration': 62,
  'achievements': ['最高排名1'],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('三类数据写入后能各自读回，互不覆盖', () async {
    final cache = DiscoverCache();
    final fetchedAt = DateTime(2026, 10, 30, 12);

    await cache.writeHotSongs(
      HotSongsCache(
        songs: [_hotSong()],
        fetchedAt: fetchedAt,
        listId: 445,
        period: 229,
        publishedAt: DateTime(2026, 10, 29),
      ),
    );
    await cache.writeMusicRank(
      MusicRankCache(
        items: [_music('BV1')],
        fetchedAt: fetchedAt,
        note: '榜单说明',
      ),
    );
    await cache.writeMusicFeed(
      MusicFeedCache(items: [_music('BV2')], fetchedAt: fetchedAt, page: 2),
    );

    final hot = await cache.readHotSongs();
    expect(hot, isNotNull);
    expect(hot!.listId, 445);
    expect(hot.period, 229);
    expect(hot.publishedAt, DateTime(2026, 10, 29));
    expect(hot.fetchedAt, fetchedAt);
    expect(hot.songs.single.title, '新·与天齐');
    expect(hot.songs.single.bvid, 'BV1nnnp6SE4D');

    final rank = await cache.readMusicRank();
    expect(rank, isNotNull);
    expect(rank!.note, '榜单说明');
    expect(rank.items.single.id, 'BV1');
    expect(rank.items.single.duration, const Duration(seconds: 61));

    final feed = await cache.readMusicFeed();
    expect(feed, isNotNull);
    expect(feed!.page, 2);
    expect(feed.items.single.id, 'BV2');
  });

  test('没有缓存时返回 null', () async {
    final cache = DiscoverCache();
    expect(await cache.readHotSongs(), isNull);
    expect(await cache.readMusicRank(), isNull);
    expect(await cache.readMusicFeed(), isNull);
  });

  test('坏掉的缓存当作没有，不抛异常', () async {
    SharedPreferences.setMockInitialValues({
      DiscoverCache.hotSongsKey: '{ 这不是 JSON',
    });
    final cache = DiscoverCache();
    expect(await cache.readHotSongs(), isNull);
    expect(await cache.readMusicRank(), isNull);

    // 写入会把整份缓存覆盖成合法 JSON
    await cache.writeMusicRank(
      MusicRankCache(items: [_music('BV1')], fetchedAt: DateTime.now()),
    );
    expect(await cache.readMusicRank(), isNotNull);
  });

  test('clear 清掉整份缓存', () async {
    final cache = DiscoverCache();
    await cache.writeMusicRank(
      MusicRankCache(items: [_music('BV1')], fetchedAt: DateTime.now()),
    );
    await cache.clear();
    expect(await cache.readMusicRank(), isNull);
  });

  group('isCacheFresh', () {
    final now = DateTime(2026, 10, 31, 12);

    test('没有抓取时间一律算过期', () {
      expect(isCacheFresh(null, hotSongsTtl, now: now), isFalse);
    });

    test('按 TTL 判定', () {
      expect(
        isCacheFresh(
          now.subtract(const Duration(hours: 1)),
          hotSongsTtl,
          now: now,
        ),
        isTrue,
      );
      expect(
        isCacheFresh(
          now.subtract(const Duration(hours: 13)),
          hotSongsTtl,
          now: now,
        ),
        isFalse,
      );
      expect(
        isCacheFresh(
          now.subtract(const Duration(minutes: 31)),
          musicFeedTtl,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
