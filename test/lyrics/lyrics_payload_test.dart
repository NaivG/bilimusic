import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file/file.dart' show File;
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_now/lyrics_now.dart';
import 'package:path/path.dart' as p;

import 'package:bilimusic/domain/artist.dart' as domain;
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/lyrics/lyrics_service.dart';

/// 歌词载荷的时间轴与缓存版本守门。
///
/// 这里盯的是两条**跨库契约**：
/// 1. 普通 LRC 没有行时长，lyrics_now 0.3.1 起只把「结束时间未知」的行截到
///    上限，剩下的空白留给器乐间奏 —— flutter_lyric 4.1 的倒计时圆点靠它触发。
/// 2. 旧缓存里的普通 LRC 时间轴是伪造的（行尾拉到下一行起点），升级后必须
///    丢弃重抓；逐字文档不受影响，不要顺手把整个歌词缓存作废。
void main() {
  late Directory cacheDir;
  late _FakeLyricsCache cache;
  late LyricsService service;

  Music sampleMusic() => Music(
    id: 'BV1xx411c7mD',
    cid: '12345',
    title: '晴天',
    artist: const domain.Artist(name: '周杰伦'),
    album: '',
    coverUrl: '',
    audioUrl: '',
  );

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('lyrics_payload');
    cache = _FakeLyricsCache(cacheDir);
  });

  tearDown(() async {
    service.dispose();
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  test('普通 LRC 的器乐间奏在时间轴上留白，够长到能显示倒计时圆点', () async {
    // 第二行唱完到第三行之间有 16 秒，远超 8 秒的行结束上限。
    const lrc = '''
[00:01.00]第一行
[00:04.00]第二行
[00:20.00]第三行
''';
    service = LyricsService(cache: cache, finder: _LrcFinder(lrc));

    final payload = await service.prefetch(sampleMusic());
    final lines = payload!.autoPayload!.document.lines;

    expect(lines.map((l) => l.start.inMilliseconds), [1000, 4000, 20000]);
    // 行距没超过上限：行尾照旧拉到下一行起点，绝大多数行的行为不变。
    expect(lines[0].end, const Duration(seconds: 4));
    // 行距 16 秒：第二行在 12 秒（4+8）收尾，12~20 秒是真正的间奏空白。
    expect(lines[1].end, const Duration(seconds: 12));
    expect(
      lines[2].start - lines[1].end!,
      greaterThanOrEqualTo(const Duration(seconds: 3)),
      reason: '空白达到 _countdown.dotDuration（3 秒）圆点才会出现',
    );
    // 普通 LRC 的合成整行 word 必须丢掉，否则 4.x 不会按字素簇重新切分，
    // 逐字上弹会退化成整行一起弹。
    expect(lines.every((l) => l.words == null || l.words!.isEmpty), isTrue);
  });

  test('普通 LRC 被判成行级，逐字时间只留给 verbatim', () async {
    final parsed = parseLrc('[00:01.00]第一行\n[00:04.00]第二行');
    final enhanced = parseLrc('[00:01.00]<00:01.00>第<00:02.00>二行');

    expect(judgeLyricsType(parsed.data), LyricsType.lineByLine);
    expect(judgeLyricsType(enhanced.data), LyricsType.verbatim);
  });

  test('v1 缓存里没有逐字时间的载荷：丢弃重抓', () async {
    final music = sampleMusic();
    await _seedPayload(
      cache,
      music,
      payload: _payload(music, model: _wordlessModel),
    );
    final finder = _CountingFinder();
    service = LyricsService(cache: cache, finder: finder);

    final result = await service.prefetch(music);

    expect(finder.searchCount, 1, reason: '旧时间轴没法就地修正，只能重新搜一次');
    expect(result?.autoPayload, isNull);
  });

  test('v1 缓存里的逐字载荷：行尾来自歌词源，继续命中', () async {
    final music = sampleMusic();
    await _seedPayload(
      cache,
      music,
      payload: _payload(music, model: _wordedModel),
    );
    final finder = _CountingFinder();
    service = LyricsService(cache: cache, finder: finder);

    final result = await service.prefetch(music);

    expect(finder.searchCount, 0, reason: '升级不该把整个歌词库拖去重新联网搜');
    expect(result?.autoPayload, isNotNull);
  });

  test('服务自己写出来的载荷（普通 LRC）再读回来仍然命中', () async {
    final music = sampleMusic();
    service = LyricsService(
      cache: cache,
      finder: _LrcFinder('[00:01.00]第一行\n[00:04.00]第二行'),
    );
    await service.prefetch(music);
    service.dispose();

    final finder = _CountingFinder();
    service = LyricsService(cache: cache, finder: finder);

    final result = await service.prefetch(music);

    expect(finder.searchCount, 0, reason: '新写的载荷已经是当前版本，不能再被丢弃');
    expect(result?.autoPayload?.document.lines.length, 2);
  });
}

const Map<String, Object?> _wordlessModel = {
  'tags': <String, Object?>{},
  'lines': [
    {'start': 0, 'end': 3000, 'text': '第一行', 'words': <Object?>[]},
  ],
};

const Map<String, Object?> _wordedModel = {
  'tags': <String, Object?>{},
  'lines': [
    {
      'start': 0,
      'end': 3000,
      'text': '第一行',
      'words': [
        {'start': 0, 'end': 3000, 'text': '第一行'},
      ],
    },
  ],
};

Map<String, Object?> _payload(
  Music music, {
  required Map<String, Object?> model,
}) => {
  'sourceId': 'lrclib:42',
  'offsetMs': 0,
  'songKey': LyricsService.songKeyOf(music),
  'model': model,
};

/// 塞一份**带版本号之前**的载荷（v1）：没有 `v` 字段，行尾是旧解析器伪造的。
Future<void> _seedPayload(
  _FakeLyricsCache cache,
  Music music, {
  required Map<String, Object?> payload,
}) async {
  final raw = jsonEncode(payload);
  await cache.putFile(
    'lyrics:payload:${LyricsService.songKeyOf(music)}',
    Uint8List.fromList(utf8.encode(raw)),
    fileExtension: 'json',
  );
}

/// 回一段真实 LRC 的检索器，走的是和线上 provider 一样的解析 + 定级路径。
class _LrcFinder implements LyricFinder {
  _LrcFinder(this.lrc);

  final String lrc;

  @override
  Future<APIResultList<SongInfo>> searchSongs(SearchQuery query) async {
    return APIResultList<SongInfo>(
      items: [
        SongInfo(
          source: Source.lrclib,
          title: '晴天',
          id: '42',
          duration: 240000,
        ),
      ],
    );
  }

  @override
  Future<Lyrics?> fetchLyrics({
    required SongInfo song,
    int durationMs = 0,
  }) async {
    final parsed = parseLrc(lrc);
    final lyrics = Lyrics.fromSong(song);
    lyrics[TrackNames.orig] = parsed.data;
    lyrics.types[TrackNames.orig] = judgeLyricsType(parsed.data);
    return lyrics;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '测试未实现的 LyricFinder 成员：${invocation.memberName}',
  );
}

/// 只记录「有没有真的去联网搜」的检索器。
class _CountingFinder implements LyricFinder {
  int searchCount = 0;

  @override
  Future<APIResultList<SongInfo>> searchSongs(SearchQuery query) async {
    searchCount++;
    return APIResultList<SongInfo>(items: const []);
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
