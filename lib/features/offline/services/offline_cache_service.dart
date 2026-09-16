// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/database.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/models/offline_track.dart';

/// 离线缓存服务：把音频流落盘到**用户可见的长期目录**，并记入 `downloads` 表。
///
/// 与 [musicCacheManager]（flutter_cache_manager 临时缓存）的分工：
/// - 临时缓存：播放时顺手落盘，随时可能被回收，用户无感知；
/// - 本服务：用户显式下载，文件长期保留、可被资源管理器直接看到。
///
/// 目录策略：
/// - 桌面端：默认 `<应用支持目录>/offline_music`，用户可在设置页改到任意目录；
/// - Android：应用私有外部目录 `<external>/Android/data/<pkg>/files/Music`，
///   **不需要任何存储权限**；此处不暴露选目录——`file_picker.getDirectoryPath`
///   在 Android 虽然返回真实绝对路径，但那是通过存储框架拿到的，没有
///   `MANAGE_EXTERNAL_STORAGE` 时第三方 ROM 上写外部公共目录会被拒。
///   离线缓存的用途只有"写自己下的音频 + 读回来播"，私有目录已经完全够用，
///   因此不请求该敏感权限（Google Play 对它的审核也很严）。
///
/// 落盘格式：B 站 DASH 音频流本身就是一个自包含的 audio-only MP4
/// （ftyp → moov → moof/sidx），mpv 与 ExoPlayer 都能直接解码，
/// **无需转码**，仅在命名时给上 `.m4a` 后缀。
class OfflineCacheService extends ChangeNotifier {
  OfflineCacheService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const String KEY_BASE_DIR = 'offline_base_dir';

  /// 默认子目录名（桌面端 / 兜底）
  static const String DEFAULT_DIR_NAME = 'offline_music';

  /// Android 应用私有外部目录下的子目录名
  static const String ANDROID_DIR_NAME = 'Music';

  /// 音质档次，用于判断"已有文件是否够用"（数值越大越高）
  static const Map<String, int> _qualityRank = {
    '30216': 1, // 64K
    '30232': 2, // 132K
    '30280': 3, // 192K
    '30250': 4, // 杜比全景声
    '30251': 5, // Hi-Res 无损
  };

  /// HTTP 客户端。非 final：测试通过 [overrideForTest] 换成替身。
  http.Client _http;

  Database? _db;
  String? _baseDir;

  final Map<String, DownloadProgress> _progress = {};
  final Set<String> _cancelled = {};
  final StreamController<Map<String, DownloadProgress>> _progressStream =
      StreamController.broadcast();

  bool _initialized = false;

  /// 当前下载进度快照（key → 进度），供 UI 直接消费。
  Map<String, DownloadProgress> get progress => Map.unmodifiable(_progress);

  /// 下载进度流（每次进度变化推一次完整快照），供 Provider 层订阅。
  Stream<Map<String, DownloadProgress>> get progressStream =>
      _progressStream.stream;

  /// 当前生效的离线目录（[initialize] 之后非空）。
  String? get baseDirectory => _baseDir;

  /// 桌面端可自选目录；Android 走应用私有外部目录，不在 UI 暴露选目录。
  ///
  /// 平台判断用 `defaultTargetPlatform` 而非 `Platform.isX`：本文件已经
  /// import 了 `dart:io`（文件操作必需），再用 PlatformHelper 会让 Web 构建
  /// 多背一层 dart:io 依赖，没必要。
  static bool get supportsDirectoryPicker => _isDesktop && !kIsWeb;

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _db = await AppDatabase.instance.database;
    _baseDir = await _resolveBaseDirectory();
  }

  /// 测试用：直接注入 DB、离线目录与 HTTP 客户端，跳过 App 单例依赖。
  ///
  /// `initialize()` 会依赖 `AppDatabase` 单例与 `path_provider`（都需要
  /// Flutter binding 和真实设备目录），单测里用这个口子把三者换成替身，
  /// 就能在内存库里跑完整的下载/查表/删除流程。
  @visibleForTesting
  void overrideForTest({
    required Database db,
    required String baseDir,
    http.Client? httpClient,
  }) {
    _db = db;
    _baseDir = baseDir;
    _initialized = true;
    if (httpClient != null) {
      _http = httpClient;
    }
  }

  // ====================================================================
  //  目录
  // ====================================================================

  /// 解析离线目录：用户配置优先，否则按平台给默认值。目录不存在则创建。
  Future<String> _resolveBaseDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString(KEY_BASE_DIR);
    if (configured != null && configured.isNotEmpty) {
      final dir = Directory(configured);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }
    return _defaultBaseDirectory();
  }

  Future<String> _defaultBaseDirectory() async {
    String dir;
    if (_isAndroid) {
      // 应用私有外部目录：无需权限，卸载时随应用一起清理。
      final external = await getExternalStorageDirectories(
        type: StorageDirectory.music,
      );
      final base = external != null && external.isNotEmpty
          ? external.first.path
          : (await getApplicationSupportDirectory()).path;
      dir = p.join(base, ANDROID_DIR_NAME);
    } else {
      final support = await getApplicationSupportDirectory();
      dir = p.join(support.path, DEFAULT_DIR_NAME);
    }
    final d = Directory(dir);
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d.path;
  }

  /// 弹出系统目录选择器并切换离线目录（仅桌面端）。
  ///
  /// Android 不暴露这个入口：见类注释——想在公共目录自由读写就得要
  /// `MANAGE_EXTERNAL_STORAGE`，而离线缓存并不需要那个能力。
  ///
  /// 已下载的文件**不会**被搬走：切换目录后旧记录会因 `exists()` 兜底失效，
  /// 用户需要在新目录重新下载（保持实现简单，避免跨盘移动大文件失败）。
  Future<String?> chooseBaseDirectory() async {
    if (!supportsDirectoryPicker) return null;
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择离线缓存目录',
    );
    if (picked == null || picked.isEmpty) return null;
    if (picked == _baseDir) return _baseDir;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_BASE_DIR, picked);
    _baseDir = picked;
    final dir = Directory(picked);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // 旧目录的记录仍指向旧绝对路径，播放时靠 exists() 判断；
    // 这里只清掉"文件已不在"的悬挂记录，不动文件本体。
    await purgeMissing();
    _broadcastProgress();
    notifyListeners();
    return picked;
  }

  /// 恢复默认目录（桌面端回到应用支持目录，Android 一律是应用私有目录）。
  Future<void> resetBaseDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KEY_BASE_DIR);
    _baseDir = await _defaultBaseDirectory();
    _broadcastProgress();
    notifyListeners();
  }

  // ====================================================================
  //  查表
  // ====================================================================

  /// 查离线记录；文件已被用户在资源管理器里删掉时顺手清掉这条记录。
  ///
  /// 这是**播放前的校验点**：`getAudioUrl` 第一步就走这里，查不到（或文件已不可用）
  /// 就返回 null，调用方随即回退到临时缓存/联网重新取流并重新登记。
  Future<OfflineTrack?> find(String bvid, String cid) async {
    await initialize();
    final rows = await _db!.query(
      'downloads',
      where: 'bvid = ? AND cid = ?',
      whereArgs: [bvid, cid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final track = OfflineTrack.fromRow(rows.first);
    if (!await _isPlayableFile(track.filePath)) {
      await remove(bvid, cid, deleteFile: false);
      return null;
    }
    return track;
  }

  /// 本地文件是否还能拿去播：**存在且非空**。
  ///
  /// 0 字节文件（下载中途被杀、磁盘写满）同样算不可用——它播不了，而且留着会害得
  /// 重新落盘时同名让位成 `xxx (1).m4a`，白攒一个孤儿。所以这里顺手把它删掉；
  /// 记录由调用方（[find] / [purgeMissing]）负责清。
  Future<bool> _isPlayableFile(String path) async {
    if (path.isEmpty) return false;
    final file = File(path);
    try {
      if (!await file.exists()) return false;
      if (await file.length() > 0) return true;
      await file.delete();
      debugPrint('[OfflineCache] 清掉 0 字节的离线文件 $path');
    } catch (e) {
      // 目录不可读/文件被独占等异常一律按"不可用"处理，让调用方重新联网取流。
      debugPrint('[OfflineCache] 校验离线文件失败 $path: $e');
      return false;
    }
    return false;
  }

  /// 该音质能否直接用已有文件：文件音质 >= 请求音质即够用；
  /// 请求档位比文件高时返回 false，由调用方决定是否重下（不静默降级）。
  bool isQualitySufficient(OfflineTrack track, String requestedQualityId) {
    final have = _qualityRank[track.qualityId] ?? 0;
    final want = _qualityRank[requestedQualityId] ?? 0;
    if (want == 0) return true; // 未知档位不做判断，直接用
    return have >= want;
  }

  /// 解析可离线播放的本地路径：
  /// 命中且音质够用 → 返回文件路径与实际音质；否则返回 null（调用方回退网络）。
  Future<({String path, String qualityId})?> resolveLocal(
    Music music, {
    String qualityId = '30280',
  }) async {
    final cid = _effectiveCid(music);
    final track = await find(music.id, cid);
    if (track == null) return null;
    if (!isQualitySufficient(track, qualityId)) return null;
    return (path: track.filePath, qualityId: track.qualityId);
  }

  /// 列出全部离线记录（最近下载在前）。
  Future<List<OfflineTrack>> listAll() async {
    await initialize();
    final rows = await _db!.query('downloads', orderBy: 'downloaded_at DESC');
    return rows.map(OfflineTrack.fromRow).toList();
  }

  /// 离线曲目总数。
  Future<int> count() async {
    await initialize();
    final result = await _db!.rawQuery('SELECT COUNT(*) AS c FROM downloads');
    return (result.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 离线占用字节数（按入库时记录的大小累加）。
  Future<int> totalBytes() async {
    await initialize();
    final result = await _db!.rawQuery(
      'SELECT SUM(file_size) AS s FROM downloads',
    );
    return (result.first['s'] as num?)?.toInt() ?? 0;
  }

  // ====================================================================
  //  下载
  // ====================================================================

  /// 下载并写入离线目录，成功后记入 `downloads` 表。
  ///
  /// [audioUrl] 应带 B 站签名的 `range` 查询参数（直接把 `baseUrl` 透传即可），
  /// 请求头必须带 Referer/UA，否则 CDN 会返回 403。
  ///
  /// [onProgress] 可选，用于调用方自己的进度展示；服务内部的 [progress] 快照
  /// 会自动维护（UI 可 watch 本 ChangeNotifier）。
  Future<OfflineTrack> download({
    required Music music,
    required String audioUrl,
    required String qualityId,
    bool replace = false,
    void Function(DownloadProgress)? onProgress,
  }) async {
    await initialize();
    final existingRecord = await find(music.id, _effectiveCid(music));
    if (!replace &&
        existingRecord != null &&
        isQualitySufficient(existingRecord, qualityId) &&
        existingRecord.filePath.isNotEmpty) {
      return existingRecord;
    }

    final cid = _effectiveCid(music);
    final dir = Directory(_baseDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final finalPath = await _allocatePath(dir, music, cid);
    // 先写 .part 再改名：中途失败/取消不会留下"看起来完整"的残缺文件。
    final tempPath = '$finalPath.part';
    final tempFile = File(tempPath);
    final key = '${music.id}_$cid';
    // 同一首曲子的下载只允许跑一个：否则两个流会争抢同一个目标路径，
    // 第二个被改名成 "(1).m4a" 而表里只留一条记录，磁盘上多一个孤儿文件。
    if (_progress.containsKey(key)) {
      throw StateError('该曲目正在下载中');
    }
    _cancelled.remove(key);

    final progress = DownloadProgress(
      key: key,
      title: music.title,
      received: 0,
      total: 0,
    );
    _emit(progress);

    try {
      final request = http.Request('GET', Uri.parse(audioUrl));
      request.headers.addAll({
        'User-Agent': NetworkConfig.userAgent,
        'Referer': 'https://www.bilibili.com',
      });
      final response = await _http.send(request);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: request.url);
      }

      final total = response.contentLength ?? 0;
      final sink = tempFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (_cancelled.contains(key)) {
            throw const _DownloadCancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          final snapshot = DownloadProgress(
            key: key,
            title: music.title,
            received: received,
            total: total,
          );
          _emit(snapshot, onProgress: onProgress);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // 原子改名：目标已存在时（同曲不同分P重名）追加序号，避免覆盖用户文件。
      var target = finalPath;
      var index = 1;
      while (await File(target).exists()) {
        target = _withSuffix(finalPath, index++);
      }
      final file = await tempFile.rename(target);

      // 重下（常见于"换到更高音质"）时，旧文件会在目标名上被让位成 "(1).m4a"，
      // 表的记录又指向新文件——不删旧的就是一个永远查不到的孤儿文件。
      await _deleteReplacedFile(existingRecord, file.path);

      final track = OfflineTrack(
        bvid: music.id,
        cid: cid,
        title: music.title,
        artist: music.artist,
        filePath: file.path,
        qualityId: qualityId,
        fileSize: received,
        downloadedAt: DateTime.now(),
      );
      await _upsert(track);

      _progress.remove(key);
      _broadcastProgress();
      notifyListeners();
      return track;
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      _progress.remove(key);
      _broadcastProgress();
      notifyListeners();
      if (e is _DownloadCancelled) {
        debugPrint('[OfflineCache] 已取消 $key');
      }
      rethrow;
    }
  }

  /// 取消进行中的下载（仅对当前进程内正在跑的下载有效）。
  void cancel(String bvid, String cid) {
    _cancelled.add('${bvid}_$cid');
  }

  bool isDownloading(String bvid, String cid) =>
      _progress.containsKey('${bvid}_$cid');

  /// 把"已经在临时缓存里的文件"另存进离线目录。
  ///
  /// 这是**显式下载入口**（`OfflineTracksNotifier.download`）用的落盘方式：
  /// 音频已经躺在 flutter_cache_manager 里，没必要再从网络拉一遍。
  /// 同一文件系统内用 rename（原子、瞬间完成，还会把文件从临时缓存移走），
  /// 跨盘则退化成复制——此时**不删源文件**，因为播放器可能正打开着它。
  ///
  /// 播放链路不会调它：临时缓存是滚动回收的，永久离线目录只放用户主动下载的东西。
  Future<OfflineTrack?> persistFromFile({
    required Music music,
    required String sourcePath,
    required String qualityId,
    bool replace = false,
  }) async {
    await initialize();
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final cid = _effectiveCid(music);
    // 无论是否 replace 都查一次旧记录：replace=false 时用来判"已有音质够不够用"，
    // 其余情况用来清掉被让位（"… (1).m4a"）的旧文件，不留孤儿。
    final existing = await find(music.id, cid);
    if (!replace &&
        existing != null &&
        isQualitySufficient(existing, qualityId)) {
      return existing;
    }

    final dir = Directory(_baseDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    var target = await _allocatePath(dir, music, cid);
    var index = 1;
    while (await File(target).exists()) {
      target = _withSuffix(target, index++);
    }

    File saved;
    try {
      saved = await source.rename(target);
    } on FileSystemException {
      // 跨卷 rename 会抛异常，退化为复制；源文件留给临时缓存自生自灭。
      saved = await source.copy(target);
    }

    final track = OfflineTrack(
      bvid: music.id,
      cid: cid,
      title: music.title,
      artist: music.artist,
      filePath: saved.path,
      qualityId: qualityId,
      fileSize: await saved.length(),
      downloadedAt: DateTime.now(),
    );
    // 升级音质时新文件会以 "… (1).m4a" 让位，旧文件得删掉，否则永远查不到它。
    await _deleteReplacedFile(existing, saved.path);
    await _upsert(track);
    _broadcastProgress();
    notifyListeners();
    return track;
  }

  /// 删掉被新落盘文件取代的旧文件（重下/升级音质后遗留）。
  ///
  /// 目标名被占时新文件会退让成 `xxx (1).m4a`，表里只指向新文件，
  /// 不删旧的就是一个用户看不见、也永远查不到的孤儿文件。
  Future<void> _deleteReplacedFile(
    OfflineTrack? replaced,
    String newPath,
  ) async {
    if (replaced == null || replaced.filePath == newPath) return;
    final stale = File(replaced.filePath);
    if (!await stale.exists()) return;
    try {
      await stale.delete();
    } catch (e) {
      debugPrint('[OfflineCache] 清理旧版本文件失败 ${stale.path}: $e');
    }
  }

  // ====================================================================
  //  删除 / 清理
  // ====================================================================

  /// 删除离线记录。[deleteFile] 为 true 时同时删掉磁盘文件。
  Future<void> remove(String bvid, String cid, {bool deleteFile = true}) async {
    await initialize();
    if (deleteFile) {
      final rows = await _db!.query(
        'downloads',
        columns: ['file_path'],
        where: 'bvid = ? AND cid = ?',
        whereArgs: [bvid, cid],
        limit: 1,
      );
      final path = rows.isEmpty ? null : rows.first['file_path']?.toString();
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('[OfflineCache] 删除文件失败 $path: $e');
          }
        }
      }
    }
    await _db!.delete(
      'downloads',
      where: 'bvid = ? AND cid = ?',
      whereArgs: [bvid, cid],
    );
    _broadcastProgress();
    notifyListeners();
  }

  /// 清空全部离线内容（删文件 + 清表）。
  Future<void> clearAll({bool deleteFiles = true}) async {
    await initialize();
    if (deleteFiles) {
      for (final row in await _db!.query('downloads', columns: ['file_path'])) {
        final path = row['file_path']?.toString();
        if (path == null || path.isEmpty) continue;
        final file = File(path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('[OfflineCache] 删除文件失败 $path: $e');
          }
        }
      }
    }
    await _db!.delete('downloads');
    _broadcastProgress();
    notifyListeners();
  }

  /// 清理"记录还在但文件已不在"的悬挂条目（用户手动删文件后调用），
  /// 并顺手清掉上次进程异常退出留下的 `*.part` 半成品。
  Future<int> purgeMissing() async {
    await initialize();
    var removed = 0;
    for (final row in await _db!.query('downloads')) {
      final track = OfflineTrack.fromRow(row);
      if (await _isPlayableFile(track.filePath)) continue;
      await _db!.delete(
        'downloads',
        where: 'bvid = ? AND cid = ?',
        whereArgs: [track.bvid, track.cid],
      );
      removed++;
    }
    await purgeTempFiles();
    if (removed > 0) {
      _broadcastProgress();
      notifyListeners();
    }
    return removed;
  }

  /// 清掉离线目录里遗留的 `*.part` 半成品（下载中途崩溃/被杀留下的）。
  Future<int> purgeTempFiles() async {
    await initialize();
    final dir = Directory(_baseDir!);
    if (!await dir.exists()) return 0;
    var removed = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.part')) continue;
        try {
          await entity.delete();
          removed++;
        } catch (e) {
          debugPrint('[OfflineCache] 清理残留失败 ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('[OfflineCache] 扫描离线目录失败: $e');
    }
    return removed;
  }

  // ====================================================================
  //  内部工具
  // ====================================================================

  /// 分 P 归属：cid 缺失时退化为空串（与 `Music.key` 的 (id, cid) 判等一致）。
  String _effectiveCid(Music music) {
    if (music.cid.isNotEmpty) return music.cid;
    if (music.pages.isNotEmpty) return music.pages.first.cid;
    return '';
  }

  /// 公开版 [Music] → cid 解析，供上层用**同一套规则**查表。
  ///
  /// 落库 cid 走的是 [effectiveCid]（cid 缺失时取首分 P），调用方若直接拿
  /// `music.cid` 去 [find]，cid 为空的 [Music] 就会查不到自己的记录。
  String effectiveCid(Music music) => _effectiveCid(music);

  /// 写入/覆盖一条离线记录（同曲重下时按 (bvid, cid) 覆盖）。
  Future<void> _upsert(OfflineTrack track) async {
    await _db!.insert('downloads', {
      'bvid': track.bvid,
      'cid': track.cid,
      'title': track.title,
      'artist': track.artist,
      'file_path': track.filePath,
      'quality_id': track.qualityId,
      'file_size': track.fileSize,
      'downloaded_at': track.downloadedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 生成落盘路径：`<base>/<首字母>/<artist> - <title> [cid].m4a`。
  ///
  /// 首字母分目录是为了避免单目录堆几万个文件（Windows 资源管理器会明显变卡）。
  Future<String> _allocatePath(Directory base, Music music, String cid) async {
    final name = buildFileName(music, cid);
    final dir = Directory(p.join(base.path, bucketOf(name)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, '${buildFileName(music, cid)}.m4a');
  }

  /// 生成文件名（不含扩展名）：`<artist> - <title> [cid]`。
  ///
  /// 名字里带 cid，天然区分同一稿件下标题相同的不同分 P；
  /// 公开 + `@visibleForTesting` 是为了让命名规则能被单测锁定
  /// （Windows 非法字符、超长截断、方括号等坑都在这里）。
  @visibleForTesting
  static String buildFileName(Music music, String cid) {
    final artist = music.artist.trim().isEmpty ? '未知艺术家' : music.artist;
    final title = music.title.trim().isEmpty ? music.id : music.title;
    var name = sanitizeFileName('$artist - $title');
    if (name.isEmpty) name = music.id;
    if (cid.isNotEmpty) name = '$name [$cid]';
    return name;
  }

  /// 分桶目录名：ASCII 字母/数字取大写首字符，其余（含中文）统一进 `_`。
  @visibleForTesting
  static String bucketOf(String name) {
    if (name.isEmpty) return '_';
    final first = name.substring(0, 1);
    if (RegExp(r'[A-Za-z0-9]').hasMatch(first)) return first.toUpperCase();
    return '_';
  }

  /// 跨平台文件名净化：Windows 非法字符最多，一律按它来（去掉控制字符、
  /// 路径分隔符与保留字符，并裁掉结尾的点/空格——Windows 不允许）。
  ///
  /// 截断按**字符数**（80）而不是字节：中文字符 UTF-8 占 3 字节，
  /// 80 字符最坏 240 字节，仍在常见文件系统 255 字节上限之内。
  @visibleForTesting
  static String sanitizeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final trimmed = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    return trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed;
  }

  String _withSuffix(String path, int index) {
    final dir = p.dirname(path);
    final base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    return p.join(dir, '$base ($index)$ext');
  }

  void _emit(
    DownloadProgress snapshot, {
    void Function(DownloadProgress)? onProgress,
  }) {
    _progress[snapshot.key] = snapshot;
    onProgress?.call(snapshot);
    _broadcastProgress();
    notifyListeners();
  }

  void _broadcastProgress() {
    if (!_progressStream.isClosed) {
      _progressStream.add(Map.unmodifiable(_progress));
    }
  }

  @override
  void dispose() {
    _progressStream.close();
    _http.close();
    super.dispose();
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
