import 'dart:io';

import 'package:file/file.dart' as pfile;
import 'package:file/local.dart' as plocal;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/offline/services/offline_cache_service.dart';

/// 假 CDN 回的音频字节。
const String kAudioPayload = 'FAKE-M4S-BYTES-0123456789';

/// 离线缓存全链路的密封测试（`OfflineTracksNotifier.download` / `ApiService.getAudioUrl`
/// / `OfflineCacheService` 三者接线）。
///
/// 两套语义必须分清楚，这里就是它们的守门测试：
/// - **播放 / 取流**（`getAudioUrl`）：离线表 → 临时缓存 → 联网下载进临时缓存。
///   只借用滚动回收的临时缓存，**绝不写永久离线目录**，否则每播一首都永久占盘，
///   离线目录就退化成第二个播放缓存目录。
/// - **下载到离线缓存**（`OfflineTracksNotifier.download`）：把临时缓存那份改名进
///   永久离线目录并登记；用户在资源管理器里删掉文件后，下次播放会清掉这条悬挂记录、
///   重新缓存到临时目录继续播，而不是又往永久目录塞一份。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory baseDir;
  late Directory cacheDir;
  late OfflineCacheService service;
  late _FakeMusicCache musicCache;
  late ApiService api;
  late ProviderContainer container;

  Music sampleMusic() => Music(
    id: 'BV1xx411c7mD',
    cid: '12345',
    title: '晴天',
    artist: '周杰伦',
    album: '',
    coverUrl: '',
    audioUrl: '',
  );

  OfflineTracksNotifier notifier() =>
      container.read(offlineTracksProvider.notifier);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();

    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE downloads (
              bvid TEXT NOT NULL,
              cid TEXT NOT NULL,
              title TEXT,
              artist TEXT,
              file_path TEXT NOT NULL,
              quality_id TEXT,
              file_size INTEGER DEFAULT 0,
              downloaded_at INTEGER NOT NULL,
              PRIMARY KEY (bvid, cid)
            )
          ''');
        },
      ),
    );
    baseDir = await Directory.systemTemp.createTemp('offline_flow_base');
    cacheDir = await Directory.systemTemp.createTemp('offline_flow_cache');

    service = OfflineCacheService(
      // 全链路里音频走 CacheManager，这个客户端只用于构造，不该被调用。
      httpClient: MockClient(
        (_) async => http.Response('should not be called', 500),
      ),
    );
    service.overrideForTest(db: db, baseDir: baseDir.path);

    musicCache = _FakeMusicCache(cacheDir);
    api = ApiService(
      client: _FakeBiliClient(),
      musicCache: musicCache,
      // 与 app_providers.dart 的接线保持一致：只有离线查表，没有落盘钩子。
      offlineResolver: (music, qualityId) =>
          service.resolveLocal(music, qualityId: qualityId),
    );

    container = ProviderContainer(
      overrides: [
        offlineCacheServiceProvider.overrideWithValue(service),
        apiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    service.dispose();
    await db.close();
    for (final dir in [baseDir, cacheDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test('播放取流只写临时缓存，不写永久离线目录', () async {
    final audio = await api.getAudioUrl(sampleMusic(), qualityId: '30280');

    expect(audio.path, isNotEmpty);
    expect(await File(audio.path).exists(), isTrue);
    expect(p.isWithin(cacheDir.path, audio.path), isTrue, reason: '应落在临时缓存目录');
    expect(await service.count(), 0, reason: '播放不该往离线表里登记');
    expect(_audioFilesIn(baseDir), isEmpty, reason: '播放不该往离线目录写文件');
  });

  test('下载到离线缓存：把临时缓存那份改名进永久目录并登记', () async {
    // 先播一遍（音频进临时缓存），再点下载：不该重新联网。
    final played = await api.getAudioUrl(sampleMusic(), qualityId: '30280');
    expect(musicCache.downloadCount, 1);

    final track = await notifier().download(sampleMusic());

    expect(musicCache.downloadCount, 1, reason: '临时缓存已有，下载不该重新联网');
    expect(track.filePath, isNot(played.path));
    expect(p.isWithin(baseDir.path, track.filePath), isTrue);
    expect(await File(track.filePath).exists(), isTrue);
    expect(
      await File(played.path).exists(),
      isFalse,
      reason: '同盘 rename 会把源文件移走',
    );
    expect(await service.count(), 1);
    expect(_audioFilesIn(baseDir), hasLength(1));
  });

  test('清空离线缓存后再次下载同一首：不该误报落盘失败（文件其实已落盘）', () async {
    final first = await notifier().download(sampleMusic());
    expect(await File(first.filePath).exists(), isTrue);

    // 「清空离线缓存」：文件 + 记录一起删掉。
    await notifier().clearAll();
    expect(await service.count(), 0);
    expect(await File(first.filePath).exists(), isFalse);

    // 再次下载同一首：必须成功，而不是抛 StateError('落盘失败…')。
    final again = await notifier().download(sampleMusic());

    expect(await File(again.filePath).exists(), isTrue);
    expect(again.filePath, first.filePath);
    expect(await service.count(), 1);
    expect(_audioFilesIn(baseDir), hasLength(1), reason: '不能留下孤儿文件');
  });

  test('播放前校验：离线文件被外部删掉 → 清记录 + 重新缓存 + 播放临时缓存', () async {
    final track = await notifier().download(sampleMusic());
    expect(musicCache.downloadCount, 1);

    // 模拟用户在资源管理器里删掉文件：记录还在，但已成了播不了的悬挂条目。
    await File(track.filePath).delete();
    expect(await service.count(), 1, reason: '此时表里还有一条悬挂记录');

    final audio = await api.getAudioUrl(sampleMusic(), qualityId: '30280');

    expect(await File(audio.path).exists(), isTrue);
    expect(
      p.isWithin(cacheDir.path, audio.path),
      isTrue,
      reason: '重新缓存到临时缓存即可，不该再写一份进永久目录',
    );
    expect(musicCache.downloadCount, 2, reason: '悬挂记录不该被当成命中，必须重新取流');
    expect(await service.count(), 0, reason: '悬挂记录要清掉，且播放不再登记');
    expect(_audioFilesIn(baseDir), isEmpty, reason: '永久目录里那份已被用户删掉，不再补写');

    // 列表（UI 的「已下载」标记来源）也不能留下幽灵条目。
    final list = await container.read(offlineTracksProvider.future);
    expect(list, isEmpty);
  });

  test('0 字节残留文件按"不可播"处理：清记录与空文件后重新缓存', () async {
    final track = await notifier().download(sampleMusic());

    // 下载中途被杀 / 磁盘写满会留下播不了的 0 字节文件。
    await File(track.filePath).writeAsString('');

    final audio = await api.getAudioUrl(sampleMusic(), qualityId: '30280');

    expect(await File(audio.path).exists(), isTrue);
    expect(await File(audio.path).length(), greaterThan(0));
    expect(await service.count(), 0);
    expect(_audioFilesIn(baseDir), isEmpty, reason: '空文件要清掉，不留孤儿');
  });

  test('已有更低音质的离线文件时，重下并清掉旧文件', () async {
    // 造一条 64K 的旧记录（设置里请求的是 30280，判为"不够用"）。
    final source = File(p.join(cacheDir.path, 'low.m4s'));
    await source.writeAsString(kAudioPayload);
    final low = await service.persistFromFile(
      music: sampleMusic(),
      sourcePath: source.path,
      qualityId: '30216',
    );
    expect(low, isNotNull);

    final high = await notifier().download(sampleMusic());

    expect(high.qualityId, '30280');
    expect(high.filePath, isNot(low!.filePath));
    expect(await File(high.filePath).exists(), isTrue);
    expect(await File(low.filePath).exists(), isFalse, reason: '旧音质文件应被清掉');
    expect(await service.count(), 1);
    expect(_audioFilesIn(baseDir), hasLength(1), reason: '不能留下孤儿文件');
  });
}

/// 离线目录里现存的落盘产物（按 .m4a 后缀统计，含被让位成 "(1)" 的孤儿）。
List<File> _audioFilesIn(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.m4a'))
    .toList();

/// 假的 B 站客户端：只回 [ApiService.getAudioUrl] 需要的 playurl 结构。
class _FakeBiliClient extends BiliClient {
  @override
  Future<dynamic> get(
    String path, {
    Map<String, Object?>? query,
    bool signed = false,
    Map<String, String>? headers,
    Duration? timeout,
    String? baseUrl,
    bool retry = true,
  }) async {
    if (path == '/x/player/playurl') {
      return {
        'dash': {
          'audio': [
            {'id': 30280, 'baseUrl': 'https://cdn.example.com/audio.m4s?sig=1'},
          ],
        },
      };
    }
    throw UnimplementedError('测试未覆盖的接口：$path');
  }
}

/// 假的音频临时缓存（flutter_cache_manager）：语义与真实实现一致——
/// 「下载」把字节写进缓存目录并返回该文件；文件被移走后查缓存即落空
/// （真实实现会顺手删掉失效的索引行，这里用 `exists()` 模拟同一效果）。
class _FakeMusicCache implements CacheManager {
  _FakeMusicCache(this.cacheDir);

  static const plocal.LocalFileSystem _fs = plocal.LocalFileSystem();

  final Directory cacheDir;
  final Map<String, pfile.File> _entries = {};

  int downloadCount = 0;

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    downloadCount++;
    final file = _fs.file(p.join(cacheDir.path, 'download_$downloadCount.m4s'));
    await file.writeAsString(kAudioPayload);
    _entries[key ?? url] = file;
    return FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 7)),
      url,
    );
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
      DateTime.now().add(const Duration(days: 7)),
      key,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '测试未实现的 CacheManager 成员：${invocation.memberName}',
  );
}
