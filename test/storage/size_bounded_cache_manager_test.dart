import 'package:file/file.dart' as file;
import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/storage/cache_manager.dart';

/// `SizeBoundedCacheManager` 的落盘淘汰行为测试。
///
/// 全程使用内存文件系统与假索引仓库：不触发 path_provider，也不会碰真实磁盘
/// 上的音乐 / 图片缓存。`trimToBudget()` 内部已经 `await store.getCacheSize()`
/// 等索引打开，所以测试里不用手动 `repo.open()`。
void main() {
  late MemoryFileSystem memoryFs;
  late _FakeCacheInfoRepository repo;
  late SizeBoundedCacheManager manager;
  late int limitBytes;

  setUp(() {
    // 指定 posix 风格，避免 Windows 下相对路径被加上盘符，断言更直观。
    memoryFs = MemoryFileSystem(style: FileSystemStyle.posix);
    repo = _FakeCacheInfoRepository();
    limitBytes = 1024;
    manager = SizeBoundedCacheManager(
      fcm.Config(
        'size_bounded_cache_test',
        stalePeriod: const Duration(days: 1),
        maxNrOfCacheObjects: 16,
        repo: repo,
        fileSystem: _MemoryCacheFileSystem(memoryFs),
        fileService: _FakeFileService(List<int>.filled(400, 7)),
      ),
      limitBytesProvider: () => limitBytes,
    );
  });

  /// 在内存文件系统里写一个 [size] 字节的文件，并往假仓库插一条对应索引。
  Future<void> seedFile(
    String relativePath,
    int size, {
    required DateTime touched,
  }) async {
    await memoryFs.file(relativePath).writeAsBytes(List<int>.filled(size, 0));
    await repo.insert(
      fcm.CacheObject(
        'https://example.com/$relativePath',
        key: relativePath,
        relativePath: relativePath,
        validTill: DateTime.utc(2030),
        length: size,
        touched: touched,
      ),
      setTouchedToNow: false,
    );
  }

  final baseTime = DateTime.utc(2026, 1, 1, 12);
  DateTime minutesLater(int minutes) =>
      baseTime.add(Duration(minutes: minutes));

  test('超出预算时淘汰最久未用的文件，保留较新的并同步删除索引', () async {
    await seedFile('oldest.file', 500, touched: minutesLater(0));
    await seedFile('middle.file', 300, touched: minutesLater(10));
    await seedFile('newest.file', 300, touched: minutesLater(20));

    // 总量 1100 B，预算 700 B：只淘汰最久未用的 oldest（剩 600 B）。
    limitBytes = 700;
    await manager.trimToBudget();

    expect(memoryFs.file('oldest.file').existsSync(), isFalse);
    expect(repo.relativePaths, unorderedEquals(['middle.file', 'newest.file']));
    expect(memoryFs.file('middle.file').existsSync(), isTrue);
    expect(memoryFs.file('newest.file').existsSync(), isTrue);
  });

  test('删掉最旧一条仍超预算时按 LRU 继续删，绝不先删最新的', () async {
    await seedFile('tiny_oldest.file', 100, touched: minutesLater(0));
    await seedFile('big_middle.file', 600, touched: minutesLater(10));
    await seedFile('big_newest.file', 600, touched: minutesLater(20));

    // 总量 1300 B，预算 700 B：最先淘汰 tiny_oldest，仍超预算再淘汰
    // big_middle；最新的 big_newest 必须留下。
    limitBytes = 700;
    await manager.trimToBudget();

    expect(memoryFs.file('tiny_oldest.file').existsSync(), isFalse);
    expect(memoryFs.file('big_middle.file').existsSync(), isFalse);
    expect(memoryFs.file('big_newest.file').existsSync(), isTrue);
    expect(repo.relativePaths, ['big_newest.file']);
  });

  test('文件已不存在的悬空索引会被清掉，正常条目不受影响', () async {
    await seedFile('alive.file', 200, touched: minutesLater(0));
    // 只插索引不写文件，模拟上个进程删了文件却没删索引。
    await repo.insert(
      fcm.CacheObject(
        'https://example.com/gone.file',
        key: 'gone.file',
        relativePath: 'gone.file',
        validTill: DateTime.utc(2030),
        length: 300,
        touched: minutesLater(10),
      ),
      setTouchedToNow: false,
    );

    // 预算远大于总量，确保不会因为大小而淘汰任何东西。
    limitBytes = 1024 * 1024;
    await manager.trimToBudget();

    expect(repo.relativePaths, ['alive.file']);
    expect(memoryFs.file('alive.file').existsSync(), isTrue);
  });

  test('总量在预算以内时什么都不删', () async {
    await seedFile('a.file', 300, touched: minutesLater(0));
    await seedFile('b.file', 300, touched: minutesLater(10));
    await seedFile('c.file', 300, touched: minutesLater(20));

    limitBytes = 900;
    await manager.trimToBudget();

    expect(memoryFs.file('a.file').existsSync(), isTrue);
    expect(memoryFs.file('b.file').existsSync(), isTrue);
    expect(memoryFs.file('c.file').existsSync(), isTrue);
    expect(repo.relativePaths, ['a.file', 'b.file', 'c.file']);
  });

  test('刚下载写入的文件在紧接着的淘汰中受保护', () async {
    await seedFile('old.file', 100, touched: minutesLater(0));

    final info = await manager.downloadFile('https://example.com/new.mp3');
    final downloadedPath = info.file.path;

    expect(info.source, fcm.FileSource.Online);
    expect(memoryFs.file(downloadedPath).existsSync(), isTrue);

    // 预算压到 150 B：老文件 100 B + 新文件 400 B 都超预算。按 LRU 两者都该
    // 淘汰，但刚写过的文件在本轮被保护，只能删掉老文件。
    limitBytes = 150;
    await manager.trimToBudget();

    expect(
      memoryFs.file(downloadedPath).existsSync(),
      isTrue,
      reason: '刚写过的文件不该被淘汰',
    );
    expect(repo.relativePaths, [downloadedPath]);
    expect(memoryFs.file('old.file').existsSync(), isFalse);
  });
}

/// 把 `flutter_cache_manager` 的 [fcm.FileSystem] 抽象类委托给内存文件系统。
///
/// 真实实现负责拼缓存目录，这里直接使用相对路径：`createFile(name)` 返回的
/// `File.path` 与 `CacheObject.relativePath` 完全一致，保护逻辑的
/// `endsWith` 判断才符合真实场景。
class _MemoryCacheFileSystem implements fcm.FileSystem {
  _MemoryCacheFileSystem(this._fileSystem);

  final MemoryFileSystem _fileSystem;

  @override
  Future<file.File> createFile(String name) async => _fileSystem.file(name);
}

/// 只存在内存里的假缓存索引仓库。
///
/// 行为对齐 `JsonCacheInfoRepository`：插入时分配自增 id，
/// `updateOrInsert` 默认把 `touched` 刷成当前时间（LRU 排序依赖它）。
class _FakeCacheInfoRepository implements fcm.CacheInfoRepository {
  final Map<int, fcm.CacheObject> _objects = <int, fcm.CacheObject>{};
  int _nextId = 1;

  /// 当前索引里的相对路径，按插入顺序返回，便于断言哪些索引被删了。
  List<String> get relativePaths =>
      _objects.values.map((object) => object.relativePath).toList();

  @override
  Future<bool> exists() async => true;

  @override
  Future<bool> open() async => true;

  @override
  Future<dynamic> updateOrInsert(fcm.CacheObject cacheObject) {
    return cacheObject.id == null ? insert(cacheObject) : update(cacheObject);
  }

  @override
  Future<fcm.CacheObject> insert(
    fcm.CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async {
    final id = _nextId++;
    final stored = _copyWithIdAndTouched(cacheObject, id, setTouchedToNow);
    _objects[id] = stored;
    return stored;
  }

  @override
  Future<int> update(
    fcm.CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async {
    final id = cacheObject.id;
    if (id == null) {
      throw ArgumentError('更新缓存索引前必须先有 id');
    }
    _objects[id] = _copyWithIdAndTouched(cacheObject, id, setTouchedToNow);
    return 1;
  }

  fcm.CacheObject _copyWithIdAndTouched(
    fcm.CacheObject source,
    int id,
    bool setTouchedToNow,
  ) {
    return fcm.CacheObject(
      source.url,
      key: source.key,
      relativePath: source.relativePath,
      validTill: source.validTill,
      eTag: source.eTag,
      id: id,
      length: source.length,
      touched: setTouchedToNow ? DateTime.now() : source.touched,
    );
  }

  @override
  Future<fcm.CacheObject?> get(String key) async {
    for (final object in _objects.values) {
      if (object.key == key) return object;
    }
    return null;
  }

  @override
  Future<int> delete(int id) async => _objects.remove(id) == null ? 0 : 1;

  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    var deleted = 0;
    for (final id in ids) {
      if (_objects.remove(id) != null) deleted++;
    }
    return deleted;
  }

  @override
  Future<List<fcm.CacheObject>> getAllObjects() async =>
      _objects.values.toList();

  @override
  Future<List<fcm.CacheObject>> getObjectsOverCapacity(int capacity) async =>
      const <fcm.CacheObject>[];

  @override
  Future<List<fcm.CacheObject>> getOldObjects(Duration maxAge) async =>
      const <fcm.CacheObject>[];

  @override
  Future<bool> close() async => true;

  @override
  Future<void> deleteDataFile() async {}
}

/// 假网络下载服务：固定字节内容返回一次 200 响应，不碰真实网络。
class _FakeFileService extends fcm.FileService {
  _FakeFileService(this.bytes);

  final List<int> bytes;

  @override
  Future<fcm.FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    return _FakeFileServiceResponse(bytes);
  }
}

class _FakeFileServiceResponse implements fcm.FileServiceResponse {
  _FakeFileServiceResponse(this._bytes);

  final List<int> _bytes;

  @override
  Stream<List<int>> get content => Stream<List<int>>.value(_bytes);

  @override
  int? get contentLength => _bytes.length;

  @override
  String? get eTag => 'test-eTag';

  @override
  int get statusCode => 200;

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));

  @override
  String get fileExtension => '.mp3';
}
