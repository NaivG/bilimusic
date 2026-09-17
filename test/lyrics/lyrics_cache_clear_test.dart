import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file/file.dart' show File;
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_now/lyrics_now.dart';
import 'package:path/path.dart' as p;

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/lyrics/lyrics_service.dart';

/// 「清空歌词缓存」入口的守门测试。
///
/// 这里断言的不只是 `emptyCache()` 被调用，而是
/// **清空后再取同一首歌必须重新联网搜索**。
void main() {
  late Directory cacheDir;
  late _FakeLyricsCache cache;
  late _FakeFinder finder;
  late LyricsService service;

  Music sampleMusic() => Music(
    id: 'BV1xx411c7mD',
    cid: '12345',
    title: '晴天',
    artist: '周杰伦',
    album: '',
    coverUrl: '',
    audioUrl: '',
  );

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('lyrics_cache_clear');
    cache = _FakeLyricsCache(cacheDir);
    finder = _FakeFinder();
    service = LyricsService(cache: cache, finder: finder);
  });

  tearDown(() async {
    service.dispose();
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  test('清空歌词缓存后：磁盘与内存两层都失效，同一首歌必须重新搜索', () async {
    final music = sampleMusic();
    await _seedAutoPayload(cache, music);

    // 第一次预热命中磁盘缓存：不该发搜索请求，同时载荷被读进内存层。
    final beforeClear = await service.prefetch(music);
    expect(beforeClear?.autoPayload, isNotNull, reason: '磁盘缓存应该命中');
    expect(finder.searchCount, 0, reason: '命中缓存时不该联网');

    var notified = 0;
    service.addListener(() => notified++);

    await service.clearCache();

    expect(cache.emptyCount, 1, reason: '磁盘缓存要清');
    expect(notified, greaterThan(0), reason: '要通知 UI 重建，让当前曲目重新搜索');
    expect(cache.entryCount, 0, reason: '磁盘上不该留下歌词载荷');

    // 内存层若没清，这里会直接拿旧载荷秒回，searchCount 仍是 0。
    final afterClear = await service.prefetch(music);
    expect(afterClear?.autoPayload, isNull, reason: '清空后不该还能拿到旧载荷');
    expect(finder.searchCount, 1, reason: '清空后必须重新联网搜索');
  });

  test('清空前先失败冷却期内不重搜；清空后立刻重试', () async {
    final music = sampleMusic();

    // 假 finder 搜不到任何候选 → 这一次搜索记为失败，进入冷却期。
    await service.prefetch(music);
    expect(finder.searchCount, 1);

    // 冷却期内（3 分钟）不该再发搜索请求。
    await service.prefetch(music);
    expect(finder.searchCount, 1, reason: '冷却期内应直接返回，不再搜索');

    await service.clearCache();

    // 清完缓存等于「重新开始」：冷却期一并清掉，用户不必干等 3 分钟。
    await service.prefetch(music);
    expect(finder.searchCount, 2, reason: '清空后应立刻重试，而不是继续等冷却');
  });
}

/// 按 [LyricsService] 的缓存 key 约定塞一份自动选中的歌词载荷。
Future<void> _seedAutoPayload(_FakeLyricsCache cache, Music music) async {
  final raw = jsonEncode({
    'sourceId': 'qq:1',
    'offsetMs': 0,
    'songKey': LyricsService.songKeyOf(music),
    'model': {
      'tags': {'ti': music.title},
      'lines': [
        {'start': 0, 'end': 3000, 'text': '第一行', 'words': <Object?>[]},
      ],
    },
  });
  await cache.putFile(
    'lyrics:payload:${LyricsService.songKeyOf(music)}',
    Uint8List.fromList(utf8.encode(raw)),
    fileExtension: 'json',
  );
}

/// 假歌词缓存（flutter_cache_manager）：真实读写临时目录里的文件，语义与
/// 真实实现一致（`putFile` 落盘、`getFileFromCache` 命中、`emptyCache` 全清），
/// 只实现测试用到的那几个成员。
class _FakeLyricsCache implements CacheManager {
  _FakeLyricsCache(this.cacheDir);

  static const LocalFileSystem _fs = LocalFileSystem();

  final Directory cacheDir;
  final Map<String, File> _entries = {};

  int emptyCount = 0;
  int _seq = 0;

  int get entryCount => _entries.length;

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
    emptyCount++;
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

/// 假的歌词检索器：只回空搜索结果，用来观察「有没有真的去联网搜」。
class _FakeFinder implements LyricFinder {
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
