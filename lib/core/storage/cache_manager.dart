import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:bilimusic/core/storage/size_lru_cache.dart';

/// 只保留「字节预算」一条淘汰规则的 LRU 缓存管理器。
///
/// 每次写入后维护一个累计字节数，超过预算就扫描一次缓存索引，按最近使用
/// 时间从旧到新删到预算以内。预算由 [CacheBudget] 提供，设置页可调。
///
/// 淘汰放在后台跑（写入路径只 `unawaited` 记账），不阻塞播放起播；正在播放 /
/// 刚写盘的文件通过 [_recentlyWritten] 保护，避免删掉播放器正在读的文件。
class SizeBoundedCacheManager extends CacheManager {
  SizeBoundedCacheManager(super.config, {required this.limitBytesProvider});

  /// 预算来源用闭包而不是构造时取值：用户在设置里改上限之后，下一次记账就生效。
  final int Function() limitBytesProvider;

  /// 当前预算（字节）；<= 0 表示不限量。
  int get limitBytes => limitBytesProvider();

  /// 最近一次扫描得到的总字节数。null 表示本进程还没扫过，
  /// 下一次写入会先扫一遍拿到准确基数（顺带处理上个进程遗留的超额缓存）。
  int? _knownBytes;

  /// 最近一次扫描之后写入过的文件绝对路径：淘汰时跳过它们。
  final Set<String> _recentlyWritten = <String>{};

  Future<void>? _running;
  bool _pending = false;

  /// 最多记住多少个「刚写过」的路径用于淘汰保护（见 [_noteWrite]）。
  static const int _maxProtectedPaths = 1024;

  /// 立即按预算淘汰一次（改小上限、清空缓存后调用，用户不必等下一次写入）。
  Future<void> trimToBudget() {
    _knownBytes = null;
    return _kick();
  }

  /// 排队一次淘汰。同一时刻只跑一轮，运行中再触发就复用正在跑的那一轮，
  /// 并在它退出前补跑一次（[_pending]）。
  Future<void> _kick() {
    _pending = true;
    return _running ??= _runTrims();
  }

  Future<void> _runTrims() async {
    try {
      while (_pending) {
        _pending = false;
        try {
          await _trimOnce();
        } on Object catch (error, stack) {
          // 索引读不出来（例如首次启动时 path_provider 还没就绪）不该影响播放，
          // 记账保持 null，下一次写入再试。
          debugPrint('[Cache] 按大小淘汰失败: $error\n$stack');
        }
      }
    } finally {
      _running = null;
    }
  }

  /// 先同步登记「刚写过」用于保护，再异步累计字节数。
  void _noteWrite(String filePath) {
    _recentlyWritten.add(filePath);
    // 上限只用来保护最近写过的文件，没必要无限攒下去；Set 是插入有序的，
    // 丢最早的一条即可。
    if (_recentlyWritten.length > _maxProtectedPaths) {
      _recentlyWritten.remove(_recentlyWritten.first);
    }
    unawaited(_accountWrite(filePath));
  }

  Future<void> _accountWrite(String filePath) async {
    try {
      await _accountWriteImpl(filePath);
    } on Object catch (error, stack) {
      // 算错最多多扫一轮，绝不能把异常抛进写入链路。
      debugPrint('[Cache] 写入记账失败: $error\n$stack');
    }
  }

  Future<void> _accountWriteImpl(String filePath) async {
    final limit = limitBytes;
    if (limit <= 0) return;

    int size;
    try {
      size = await io.File(filePath).length();
    } on io.FileSystemException {
      // 刚写完就被上层删了，忽略即可。
      return;
    }

    final known = _knownBytes;
    if (known == null) {
      // 还没有准确基数：先扫一遍（扫描结束会把准确总量写回 _knownBytes）。
      await _kick();
      return;
    }
    final updated = known + size;
    _knownBytes = updated;
    if (updated > limit) await _kick();
  }

  Future<void> _trimOnce() async {
    final limit = limitBytes;
    final protectedPaths = Set<String>.of(_recentlyWritten);
    _recentlyWritten.clear();
    if (limit <= 0) {
      _knownBytes = null;
      return;
    }

    // CacheStore 在构造时才开始 open() 缓存索引（异步），getCacheSize() 需要等它完成
    await store.getCacheSize();

    final objects = await config.repo.getAllObjects();
    final entries = <CacheLruEntry>[];
    final objectsByPath = <String, CacheObject>{};
    final danglingIds = <int>[];

    for (final object in objects) {
      final id = object.id;
      if (id == null) continue;
      final file = await config.fileSystem.createFile(object.relativePath);
      var exists = false;
      var bytes = object.length ?? 0;
      try {
        exists = await file.exists();
        // 经 `putFile` 写入的条目没有记录 length，退回到真实文件大小。
        if (exists && bytes <= 0) bytes = await file.length();
      } on io.FileSystemException {
        exists = false;
      }
      if (!exists) {
        danglingIds.add(id);
        continue;
      }
      entries.add(
        CacheLruEntry(
          relativePath: object.relativePath,
          bytes: bytes,
          lastUsed: object.touched ?? DateTime.fromMillisecondsSinceEpoch(0),
          key: object.key,
        ),
      );
      objectsByPath[object.relativePath] = object;
    }

    if (danglingIds.isNotEmpty) {
      try {
        await config.repo.deleteAll(danglingIds);
      } on Object catch (error) {
        debugPrint('[Cache] 清理失效索引失败: $error');
      }
    }

    final total = totalBytesOf(entries);
    _knownBytes = total;
    if (total <= limit) return;

    final evictions = selectLruEvictions(entries, limitBytes: limit);
    var freed = 0;
    for (final entry in evictions) {
      final object = objectsByPath[entry.relativePath];
      if (object == null) continue;
      // 正在播放 / 正在显示的文件可能还被读着，这一轮先放过。
      if (protectedPaths.any((p) => p.endsWith(entry.relativePath))) continue;
      try {
        await store.removeCachedFile(object);
        freed += entry.bytes;
      } on Object catch (error) {
        // Windows 上删不掉被占用的文件：保留索引，下一轮再试。
        debugPrint('[Cache] 淘汰 ${entry.relativePath} 失败: $error');
      }
    }

    _knownBytes = total - freed;
    debugPrint(
      '[Cache] ${config.cacheKey} 占用 ${total - freed} B / 上限 $limit B'
      '（本轮淘汰 ${evictions.length} 个候选，实际释放 $freed B）',
    );
  }

  // 说明：这里只挂了「下载」这一条写入口（downloadFile / getFileStream）。
  // 音乐与图片缓存都只走下载，没有地方调 putFile / putFileStream——那两个
  // 入口的返回类型是 `package:file` 的 File，为它加一条直接依赖不划算。

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    final info = await super.downloadFile(
      url,
      key: key,
      authHeaders: authHeaders,
      force: force,
    );
    _noteWrite(info.file.path);
    return info;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    // 图片走 cached_network_image，它用的是 getFileStream，不是 downloadFile。
    // 只在真正下载下来（FileSource.Online）时记账，缓存命中不重复累加。
    await for (final response in super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    )) {
      if (response is FileInfo && response.source == FileSource.Online) {
        _noteWrite(response.file.path);
      }
      yield response;
    }
  }

  @override
  Future<void> emptyCache() async {
    await super.emptyCache();
    _recentlyWritten.clear();
    // 清空期间可能有一轮淘汰在飞，它结束时会把旧总量写回 _knownBytes；
    // 这里再收敛一轮（空缓存的扫描很便宜），保证清完之后基数是准的。
    await _kick();
  }
}

/// 关闭内置的「按时间淘汰」：文件不再因为多久没用而删除，只按字节预算淘汰。
/// 取 10 年是为了让 `getOldObjects()` 永远返回空表。
const Duration _keepForever = Duration(days: 3650);

/// 关闭内置的「按条数淘汰」：容量设成实际达不到的值。
/// 条数淘汰和大小预算共用同一个清理通道，只能留一个。
const int _countUnbounded = 1 << 24;

/// 音乐文件临时缓存：按大小 LRU，默认 512 MiB。
///
/// 缓存 key 仍是 `music_cache`，已经下到盘上的文件不用重下，只是淘汰策略
/// 换成 [SizeBoundedCacheManager]。
final musicCacheManager = SizeBoundedCacheManager(
  Config(
    'music_cache',
    stalePeriod: _keepForever,
    maxNrOfCacheObjects: _countUnbounded,
  ),
  limitBytesProvider: () => CacheBudget.musicLimitBytes,
);

/// 图片缓存：按大小 LRU，默认 256 MiB。
final imageCacheManager = SizeBoundedCacheManager(
  Config(
    'image_cache',
    stalePeriod: _keepForever,
    maxNrOfCacheObjects: _countUnbounded,
  ),
  limitBytesProvider: () => CacheBudget.imageLimitBytes,
);

/// 歌词缓存管理器 —— 由 `LyricsService` 写入,持久化已解析的
/// `LyricsPayload` JSON 与源列表,避免每次进入详情页都重新发起 lyrics_now 请求。
///
/// 歌词是写一条读许多条的小文本，条数上限已经够用，不参与大小 LRU。
final lyricsCacheManager = CacheManager(
  Config(
    'lyrics_cache',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 200,
  ),
);

/// 缓存清理功能
abstract class LocalStorage {
  static Future<void> clearCache() async {
    await musicCacheManager.emptyCache();
    await imageCacheManager.emptyCache();
    await lyricsCacheManager.emptyCache();
  }

  static Future<Map<String, String>> getCacheSize() async {
    final musicSize = await _getCacheSize(musicCacheManager);
    final imageSize = await _getCacheSize(imageCacheManager);
    final lyricsSize = await _getCacheSize(lyricsCacheManager);
    return {
      'music': musicSize.toString(),
      'image': imageSize.toString(),
      'lyrics': lyricsSize.toString(),
    };
  }

  static Future<int> _getCacheSize(CacheManager manager) async {
    try {
      // 获取缓存文件目录
      return await manager.store.getCacheSize();
    } catch (e) {
      return 0;
    }
  }

  /// 立即按当前预算把音乐 / 图片缓存删到上限以内。
  ///
  /// 设置页改完上限、手动清缓存之后调用：否则用户要等到下一次写入
  /// （听一首歌 / 加载一张封面）才会看到空间释放。
  static Future<void> enforceCacheLimits() async {
    await musicCacheManager.trimToBudget();
    await imageCacheManager.trimToBudget();
  }

  static Future<String> getCachePath() async {
    final cacheDir = await getTemporaryDirectory();
    return path.join(cacheDir.path, 'cache');
  }
}
