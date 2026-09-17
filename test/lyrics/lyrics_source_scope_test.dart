import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file/file.dart' show File;
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_now/lyrics_now.dart';
import 'package:path/path.dart' as p;

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/features/lyrics/lyrics_providers.dart';
import 'package:bilimusic/features/lyrics/lyrics_service.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';

/// 手动指定歌词来源的**作用域**守门测试。
void main() {
  const titleA = '甲曲';
  const titleB = '乙曲';

  late Directory cacheDir;
  late _FakeLyricsCache cache;
  late _SongFinder finder;
  late LyricsService service;
  late ProviderContainer container;
  late List<AsyncValue<LyricsPayload?>> events;

  Music music(String title) => Music(
    id: 'BV$title',
    cid: 'cid-$title',
    title: title,
    artist: '$title歌手',
    album: '',
    coverUrl: '',
    audioUrl: '',
  );

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('lyrics_source_scope');
    cache = _FakeLyricsCache(cacheDir);
    finder = _SongFinder();
    service = LyricsService(cache: cache, finder: finder);
    events = <AsyncValue<LyricsPayload?>>[];
    container = ProviderContainer(
      overrides: [
        lyricsServiceProvider.overrideWith((ref) => service),
        currentMusicProvider.overrideWith((ref) => ref.watch(_queueProvider)),
      ],
    );
    // 必须挂一个真实监听者：Riverpod 3 里没有监听者的 provider 会暂停，
    // 依赖变化不再触发重建（真实 App 里这个角色是详情页）。
    container.listen(
      currentMusicLyricsProvider,
      (_, next) => events.add(next),
      fireImmediately: true,
    );
  });

  tearDown(() async {
    container.dispose();
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  /// 等歌词 provider 稳定。
  ///
  /// 只看「事件流安静」会提前收工：异步链路（读盘缓存 → 搜索 → 取词）中间有
  /// 「暂时没有事件、但活儿还在路上」的窗口，这时 `.value` 还是上一首的载荷。
  /// 所以同时要求连续若干轮**既没有新事件、也不在 loading**。
  Future<LyricsPayload?> settle() async {
    var quiet = 0;
    for (var i = 0; i < 2000 && quiet < 30; i++) {
      await Future<void>.delayed(Duration.zero);
      final state = container.read(currentMusicLyricsProvider);
      final seen = events.length;
      await Future<void>.delayed(Duration.zero);
      if (!state.isLoading && events.length == seen) {
        quiet++;
      } else {
        quiet = 0;
      }
    }
    return container.read(currentMusicLyricsProvider).value;
  }

  String textOf(LyricsPayload? payload) => payload == null
      ? ''
      : payload.mainModel.lines.map((line) => line.text).join('/');

  test('手动选源只作用于当前曲目：切到下一首必须换成新曲子的歌词', () async {
    container.read(_queueProvider.notifier).state = music(titleA);
    expect(textOf(await settle()), contains(titleA));

    // 用户在「歌词来源」菜单里手动指定一个来源（取真实来源列表里的 id）。
    final manual = container
        .read(currentMusicLyricSourcesProvider)
        .firstWhere((source) => source.id.startsWith('ne:'));
    container
        .read(selectedLyricSourceProvider.notifier)
        .select(music(titleA), manual.id);
    expect(textOf(await settle()), contains(titleA));

    // 切到下一首。
    container.read(_queueProvider.notifier).state = music(titleB);
    final payload = await settle();

    expect(
      payload?.songKey,
      LyricsService.songKeyOf(music(titleB)),
      reason: '载荷必须属于当前曲目',
    );
    expect(
      textOf(payload),
      contains(titleB),
      reason: '切歌后必须显示新曲子的歌词，而不是把上一首的歌词贴过来',
    );
  });

  test('跨曲目的 sourceId 不许命中上一首的候选', () async {
    final resultA = await service.prefetch(music(titleA));
    final foreignId = resultA!.sources
        .firstWhere((source) => source.id != 'local')
        .id;
    await service.prefetch(music(titleB));

    final payload = await service.fetchBySourceId(foreignId, music(titleB));

    expect(payload, isNull, reason: '别的曲子的 sourceId 在本曲目里不存在，取词必须失败而不是复用它的歌词');
  });

  test('旧版本写坏的按来源缓存不许再喂给 UI', () async {
    await service.prefetch(music(titleA));
    await service.prefetch(music(titleB));
    // 旧实现会把「上一首的歌词」写进当前曲目的 key 下（sourceId 取自上一首的
    // 候选表），而读缓存发生在校验来源归属之前 —— 读回来就直接显示，
    // 于是漂移状态命中缓存后再也不会自动重取。
    final bSource = service
        .sourcesFor(music(titleB))
        .firstWhere((source) => source.id != 'local');

    final poisoned = jsonEncode({
      'sourceId': bSource.id,
      'offsetMs': 0,
      'songKey': LyricsService.songKeyOf(music(titleB)),
      'model': {
        'tags': <String, String>{},
        'lines': [
          {'start': 0, 'end': 3000, 'text': titleA, 'words': <Object?>[]},
        ],
      },
    });
    await cache.putFile(
      'lyrics:src:${LyricsService.songKeyOf(music(titleB))}:${bSource.id}',
      Uint8List.fromList(utf8.encode(poisoned)),
      fileExtension: 'json',
    );

    final payload = await service.fetchBySourceId(bSource.id, music(titleB));

    expect(
      textOf(payload),
      contains(titleB),
      reason: '缓存里那份属于上一首的载荷不能被当成当前曲目的歌词返回',
    );
  });

  test('手选来源取不到词时回退自动选源，不留着上一首的歌词', () async {
    // kg 从一开始就「搜得到候选、取不到词」，这样自动选源只会落在 ne 上。
    finder.silentSources.add(Source.kg);
    container.read(_queueProvider.notifier).state = music(titleA);
    final auto = await settle();
    expect(auto?.sourceId, startsWith('ne:'), reason: '自动选源应该落在 ne 上');

    // 用户手选 kg（在来源列表里，但取不到词）。
    final picked = container
        .read(currentMusicLyricSourcesProvider)
        .firstWhere((source) => source.id.startsWith('kg:'));
    container
        .read(selectedLyricSourceProvider.notifier)
        .select(music(titleA), picked.id);

    final payload = await settle();
    expect(
      textOf(payload),
      contains(titleA),
      reason: '手选来源没词时要回退自动选源，而不是把 null 交给 UI 一直留着旧歌词',
    );
    expect(payload?.sourceId, auto?.sourceId, reason: '回退来的载荷应该就是自动选源那份');
  });

  test('用户主动选「本地」= 不要网络歌词', () async {
    container.read(_queueProvider.notifier).state = music(titleA);
    expect(textOf(await settle()), contains(titleA));

    container
        .read(selectedLyricSourceProvider.notifier)
        .select(music(titleA), localLyricSourceId);

    expect(await settle(), isNull, reason: '「本地」不应该被回退逻辑换成网络歌词');
  });
}

/// 测试用的「当前曲目」来源，替代真实的 playlist + index 组合。
final _queueProvider = StateProvider<Music?>((_) => null);

/// 假歌词检索器：每首歌两个候选来源，歌词文本带曲名，便于分辨是谁的歌词。
class _SongFinder implements LyricFinder {
  /// 这些来源「搜得到候选、但取不到歌词」。
  final Set<Source> silentSources = <Source>{};

  @override
  Future<APIResultList<SongInfo>> searchSongs(SearchQuery query) async {
    final title = query.keyword.split(' ').first;
    return APIResultList<SongInfo>(
      items: [
        SongInfo(
          source: Source.ne,
          title: title,
          artist: Artist([query.keyword.split(' ').last]),
          id: 'ne-$title',
          duration: 200000,
        ),
        SongInfo(
          source: Source.kg,
          title: title,
          artist: Artist([query.keyword.split(' ').last]),
          hash: 'kg-$title',
          duration: 200000,
        ),
      ],
    );
  }

  @override
  Future<Lyrics?> fetchLyrics({
    required SongInfo song,
    int durationMs = 0,
  }) async {
    if (silentSources.contains(song.source)) return null;
    final lyrics = Lyrics.fromSong(song);
    lyrics[TrackNames.orig] = LyricsData([
      LyricsLine(
        start: 0,
        end: 3000,
        words: [
          LyricsWord(
            start: 0,
            end: 3000,
            text: '${song.title}-${song.source.name}',
          ),
        ],
      ),
    ]);
    lyrics.types[TrackNames.orig] = LyricsType.lineByLine;
    return lyrics;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '测试未实现的 LyricFinder 成员：${invocation.memberName}',
  );
}

/// 假歌词缓存（flutter_cache_manager）：真实读写临时目录里的文件，语义与
/// 真实实现一致（`putFile` 落盘、`getFileFromCache` 命中、`emptyCache` 全清）。
class _FakeLyricsCache implements CacheManager {
  _FakeLyricsCache(this.cacheDir);

  static const LocalFileSystem _fs = LocalFileSystem();

  final Directory cacheDir;
  final Map<String, File> _entries = {};
  int _seq = 0;

  @override
  Future<File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    final file = _fs.file(p.join(cacheDir.path, '${_seq++}.$fileExtension'));
    await file.writeAsBytes(fileBytes);
    _entries[key ?? url] = file;
    return file;
  }

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final file = _entries[key];
    if (file == null || !await file.exists()) return null;
    return FileInfo(
      file,
      FileSource.Cache,
      DateTime.now().add(const Duration(days: 30)),
      key,
    );
  }

  @override
  Future<void> emptyCache() async {
    for (final file in _entries.values) {
      if (await file.exists()) await file.delete();
    }
    _entries.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '测试未实现的 CacheManager 成员：${invocation.memberName}',
  );
}
