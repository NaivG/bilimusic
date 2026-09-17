import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/core/storage/storage_path_resolver.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/services/offline_cache_service.dart';

/// 离线缓存下载主流程的密封测试。
///
/// 用内存 SQLite + MockClient + 临时目录替换真实依赖，覆盖：
/// 流式落盘 → 登记 → 查表 → 音质判定是否触发重下 → 删除。
void main() {
  sqfliteFfiInit();
  late Database db;
  late Directory baseDir;
  late OfflineCacheService service;

  const payload = 'FAKE-M4S-BYTES-0123456789';

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
    baseDir = await Directory.systemTemp.createTemp('offline_cache_test');
    service = OfflineCacheService(
      httpClient: MockClient((request) async {
        // 模拟 CDN：带 Referer 才给流，否则 403。
        if (request.headers['Referer'] == null) {
          return http.Response('forbidden', 403);
        }
        return http.Response.bytes(
          Uint8List.fromList(payload.codeUnits),
          200,
          headers: {'content-length': '${payload.length}'},
        );
      }),
    );
    service.overrideForTest(db: db, baseDir: baseDir.path);
  });

  tearDown(() async {
    service.dispose();
    await db.close();
    if (baseDir.existsSync()) {
      await baseDir.delete(recursive: true);
    }
  });

  test('下载后落盘、登记、并能被查表命中', () async {
    final track = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s?sig=1',
      qualityId: '30280',
    );

    expect(track.filePath, endsWith('.m4a'));
    expect(await File(track.filePath).exists(), isTrue);
    expect(await File(track.filePath).readAsString(), payload);
    expect(track.fileSize, payload.length);
    expect(track.qualityId, '30280');

    // 文件名形如「周杰伦 - 晴天 [12345].m4a」，落在中文分桶目录 `_` 下。
    expect(p.basename(track.filePath), '周杰伦 - 晴天 [12345].m4a');
    expect(p.basename(p.dirname(track.filePath)), '_');

    final found = await service.find('BV1xx411c7mD', '12345');
    expect(found?.filePath, track.filePath);
    expect(await service.count(), 1);
    expect(await service.totalBytes(), payload.length);
  });

  test('重复下载同音质直接返回已有文件，不产生第二个文件', () async {
    final first = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s?sig=1',
      qualityId: '30280',
    );
    final second = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s?sig=2',
      qualityId: '30280',
    );
    expect(second.filePath, first.filePath);
    expect(await service.count(), 1);
  });

  test('HTTP 非 200 时不留下 .part 残片，也不写库', () async {
    // 换成一个只回 403 的客户端：模拟 CDN 拒绝（签名过期/缺少 Referer）。
    final failing = OfflineCacheService(
      httpClient: MockClient((_) async => http.Response('forbidden', 403)),
    );
    failing.overrideForTest(db: db, baseDir: baseDir.path);
    addTearDown(failing.dispose);

    await expectLater(
      failing.download(
        music: sampleMusic(),
        audioUrl: 'https://cdn.example.com/x.m4s',
        qualityId: '30280',
      ),
      throwsA(anything),
    );
    expect(await service.count(), 0);
    final leftovers = baseDir
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.part'));
    expect(leftovers, isEmpty);
  });

  test('升值重下不会留下孤儿文件：旧文件被删，表只指向新文件', () async {
    final low = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s',
      qualityId: '30216',
    );
    // 用 replace 强制重下更高音质（服务内部走 replaceFromFile 分支）
    final high = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s',
      qualityId: '30280',
      replace: true,
    );

    expect(high.filePath, isNot(low.filePath));
    expect(await File(low.filePath).exists(), isFalse, reason: '旧文件应被清理');
    expect(await File(high.filePath).exists(), isTrue);
    expect(await service.count(), 1);
    expect(
      (await service.find('BV1xx411c7mD', '12345'))?.filePath,
      high.filePath,
    );
  });

  test('持久化已有文件（命中临时缓存的路径）会从源文件改名过来', () async {
    final source = File(p.join(baseDir.path, 'cache-hit.m4s'));
    await source.writeAsString(payload);

    final track = await service.persistFromFile(
      music: sampleMusic(),
      sourcePath: source.path,
      qualityId: '30232',
    );

    expect(track, isNotNull);
    expect(await File(track!.filePath).readAsString(), payload);
    // 同盘 rename 会把源文件移走（临时缓存不必再留一份）。
    expect(await source.exists(), isFalse);
    expect(await service.count(), 1);
  });

  test('删除记录会同时删掉文件；文件被外部删掉时查表返回 null 并清记录', () async {
    final track = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s',
      qualityId: '30280',
    );
    await service.remove('BV1xx411c7mD', '12345');
    expect(await File(track.filePath).exists(), isFalse);
    expect(await service.count(), 0);

    // 再来一次：这次手动删文件，模拟用户在资源管理器里清理
    final again = await service.download(
      music: sampleMusic(),
      audioUrl: 'https://cdn.example.com/x.m4s',
      qualityId: '30280',
    );
    await File(again.filePath).delete();
    expect(await service.find('BV1xx411c7mD', '12345'), isNull);
    expect(await service.count(), 0);
  });

  test('清理残留会顺带清掉目录探测中途被杀留下的写探针文件', () async {
    // 模拟两处残留：探测目录时被杀留下的探针，以及下载中途被杀留下的 .part。
    final probeLeftover = File(
      p.join(baseDir.path, StoragePathResolver.probeFileName),
    );
    await probeLeftover.writeAsString('probe');
    final partLeftover = File(p.join(baseDir.path, '_', 'x.m4a.part'));
    await partLeftover.parent.create(recursive: true);
    await partLeftover.writeAsString('半成品');

    expect(await service.purgeTempFiles(), 2);
    expect(await probeLeftover.exists(), isFalse);
    expect(await partLeftover.exists(), isFalse);
  });
}
