import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_lyric/core/lyric_model.dart';

import 'package:lyrics_now/lyrics_now.dart';

import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';

/// 已解析的歌词载荷 —— 直接喂给 [LyricController.loadLyricModel]。
class LyricsPayload {
  const LyricsPayload({
    required this.sourceId,
    required this.mainModel,
    this.offsetMs = 0,
    this.songKey = '',
  });

  /// 当前选中的歌词来源 id，与 [LyricSource.id] 对应。
  final String sourceId;

  /// 已转成 flutter_lyric [LyricModel] 的歌词主体,带 ts / roma 翻译。
  final LyricModel mainModel;

  /// 歌词偏移,毫秒。
  final int offsetMs;

  /// 所属曲目键（[LyricsService.songKeyOf]）。
  ///
  /// UI 应用载荷前用它校验归属：切歌瞬间 provider 重建期间
  /// `AsyncValue.value` 返回的是上一首的旧载荷，没有这个戳就会串歌。
  /// 旧版本磁盘缓存没有该字段，读取时由服务按读取目标补戳。
  final String songKey;
}

/// 一次完整搜索的结果:候选来源 + 自动挑出的最优载荷。
class LyricsResult {
  const LyricsResult({this.sources = const [], this.autoPayload});

  /// 完整可选源列表,首项恒为 `local`。
  final List<LyricSource> sources;

  /// 自动选择的"最佳"歌词(逐字 > 行级 > null)。
  final LyricsPayload? autoPayload;
}

/// 歌词服务。
///
/// 负责:
/// - 监听 [PlayerCoordinator] 切歌,在后台预热歌词进 [CacheManager] + 内存。
/// - 暴露同步/异步方法给详情页与 UI providers。
/// - 通过 [LyricFinder] 仅发起一次 `fetchLyrics` (旧实现对每条候选都拉一次,平均 5+ 秒)。
/// - 同一首歌曲同一次预热 / 切源请求通过内存去重。
class LyricsService extends ChangeNotifier {
  LyricsService({required this.cache, required this.finder});

  final CacheManager cache;
  final LyricFinder finder;

  // in-flight 任务去重 (避免切歌 / 切源时重复请求)
  final Map<String, Future<LyricsResult?>> _inFlightResult = {};
  final Map<String, Future<LyricsPayload?>> _inFlightSource = {};

  // 搜索失败冷却：同一首歌失败后的静默期。
  // 没有它时 notifyListeners → provider rebuild → prefetch → 再搜索会形成
  // 无限重试风暴（失败不写缓存、in-flight 已被 whenComplete 清除），
  // 每轮都是全量 searchSongs + fetchLyrics，很快耗尽歌词源的限流配额。
  static const Duration _retryCooldown = Duration(minutes: 3);
  final Map<String, DateTime> _failedAt = {};

  // 内存层缓存 (避免每次都读盘)
  final Map<String, LyricsPayload> _payloadMem = {};
  final Map<String, List<LyricSource>> _sourcesMem = {};

  /// 每首曲目的候选表：`songKey → (sourceId → SongInfo)`。
  ///
  /// 必须按曲目分组。sourceId 是「来源 + 该来源里这首歌的 id」（`ne:123456`），
  /// 只在它所属曲目的候选表里有意义；旧实现是一张全局的 `sourceId → SongInfo`，
  /// 把别的曲子的 id 递进来会命中那首曲子的候选，拉回它的歌词再贴上当前曲目的
  /// songKey 返回 —— UI 的 songKey 归属校验也因此失效（表现为切歌后歌词不动）。
  final Map<String, Map<String, SongInfo>> _songBySourceId = {};

  // 监听 coordinator
  PlayerCoordinator? _coordinator;
  String? _prefetchKey;
  VoidCallback? _removeIndexListener;

  // ==================== 绑定 PlayerCoordinator ====================

  void bind(PlayerCoordinator coordinator) {
    if (_coordinator == coordinator) return;
    _unbind();
    _coordinator = coordinator;

    final notifier = coordinator.currentIndexNotifier;
    void onIndexChange() {
      final music = coordinator.currentMusic;
      if (music == null) return;
      _maybePrefetch(music);
    }

    notifier.addListener(onIndexChange);
    _removeIndexListener = () => notifier.removeListener(onIndexChange);

    final initial = coordinator.currentMusic;
    if (initial != null) _maybePrefetch(initial);
  }

  void _unbind() {
    _removeIndexListener?.call();
    _removeIndexListener = null;
    _coordinator = null;
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _maybePrefetch(Music music) {
    final key = songKeyOf(music);
    if (key == _prefetchKey) return;
    _prefetchKey = key;
    // fire-and-forget:错误被内部吞掉,不会影响 UI
    unawaited(prefetch(music));
  }

  // ==================== 公开 API ====================

  /// 同步返回当前已知的来源列表 (缓存 miss 时为空)。
  List<LyricSource> sourcesFor(Music music) {
    return _sourcesMem[songKeyOf(music)] ?? const <LyricSource>[];
  }

  /// 异步获取 (或返回缓存) 当前歌曲的主歌词载荷。
  Future<LyricsPayload?> lyricsFor(Music music) async {
    final result = await prefetch(music);
    return result?.autoPayload;
  }

  /// 切换歌词来源 —— 已缓存直接返回;未缓存通过 [LyricFinder.fetchLyrics]
  /// 走单一来源(节省旧实现对全部候选串行重试的开销)。
  ///
  /// in-flight 注册必须先于任何异步 IO（含读盘缓存），否则两个并发调用
  /// 会同时穿过检查、重复发起请求。
  Future<LyricsPayload?> fetchBySourceId(String sourceId, Music music) async {
    if (sourceId == localLyricSourceId) return null;

    final songKey = songKeyOf(music);
    final inflightKey = '$songKey::$sourceId';
    final pending = _inFlightSource[inflightKey];
    if (pending != null) return pending;

    // 命中内存缓存的 payload
    final mem = _payloadMem[inflightKey];
    if (mem != null) return mem;

    return _inFlightSource.putIfAbsent(
      inflightKey,
      () => _fetchSourceTask(sourceId, music, songKey, inflightKey),
    );
  }

  Future<LyricsPayload?> _fetchSourceTask(
    String sourceId,
    Music music,
    String songKey,
    String inflightKey,
  ) async {
    try {
      // 命中磁盘缓存的 payload
      final cached = await _readPayloadCacheFile(music, sourceId);
      if (cached != null) {
        _payloadMem[inflightKey] = cached;
        return cached;
      }

      var song = _candidatesOf(songKey)[sourceId];
      if (song == null) {
        // 本曲目还没预热（或者这个 id 压根不属于本曲目）：先完整预热一次拿候选，
        // 仍然没有就认输 —— 绝不去翻别的曲子的候选。
        await prefetch(music);
        song = _candidatesOf(songKey)[sourceId];
        if (song == null) return null;
      }

      final lyrics = await finder.fetchLyrics(song: song);
      if (lyrics == null) return null;
      final payload = _buildPayload(
        lyrics,
        sourceId: sourceId,
        songKey: songKey,
      );
      _payloadMem[inflightKey] = payload;
      await _writePayloadCacheFile(music, sourceId, payload);
      notifyListeners();
      return payload;
    } catch (e) {
      debugPrint('[LyricsService] fetchBySourceId failed: $e');
      return null;
    } finally {
      _inFlightSource.remove(inflightKey);
    }
  }

  /// 后台预热:搜索 + 单次 `fetchLyrics` + 写缓存。
  ///
  /// in-flight 注册先于任何异步 IO（含读盘缓存）：`currentIndexNotifier` 的
  /// 同步监听与 provider rebuild 几乎同时各调一次本方法，若先 await 再注册，
  /// 两次调用都会穿过检查，同一首歌并发跑两轮全量搜索。
  Future<LyricsResult?> prefetch(Music music) async {
    final songKey = songKeyOf(music);
    final pending = _inFlightResult[songKey];
    if (pending != null) return pending;

    // 内存缓存命中直接返回（旧实现只写不读，导致每次 rebuild 都走读盘）
    final mem = _payloadMem[songKey];
    if (mem != null) {
      return LyricsResult(
        sources:
            _sourcesMem[songKey] ??
            const [LyricSource(id: localLyricSourceId, name: '')],
        autoPayload: mem,
      );
    }

    return _inFlightResult.putIfAbsent(
      songKey,
      () => _prefetchTask(music, songKey),
    );
  }

  Future<LyricsResult?> _prefetchTask(Music music, String songKey) async {
    try {
      // 1) 读 payload + sources 磁盘缓存(双文件)
      final cachedPayload = await _readAutoPayloadCache(music);
      final cachedSources = await _readSourcesCache(music);

      if (cachedPayload != null) {
        _payloadMem[songKey] = cachedPayload;
        if (cachedSources != null) _sourcesMem[songKey] = cachedSources;
        return LyricsResult(
          sources:
              cachedSources ??
              const [LyricSource(id: localLyricSourceId, name: '')],
          autoPayload: cachedPayload,
        );
      }

      // 2) 失败冷却期内直接返回已知来源，不重新搜索（防重试风暴）
      final failedAt = _failedAt[songKey];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < _retryCooldown) {
        return LyricsResult(
          sources:
              _sourcesMem[songKey] ??
              const [LyricSource(id: localLyricSourceId, name: '')],
          autoPayload: null,
        );
      }

      // 3) 全量搜索
      return await _doPrefetch(music, songKey);
    } finally {
      _inFlightResult.remove(songKey);
    }
  }

  Future<LyricsResult?> _doPrefetch(Music music, String songKey) async {
    final durationMs = music.duration?.inMilliseconds ?? 0;
    final localOption = LyricSource(id: localLyricSourceId, name: music.title);
    final sources = <LyricSource>[localOption];
    LyricsPayload? autoPayload;

    try {
      final results = await finder.searchSongs(
        SearchQuery(
          keyword: '${music.title} ${music.artist}',
          searchType: SearchType.song,
          durationMs: durationMs > 0 ? durationMs : null,
        ),
      );

      // 记录每条候选的 SongInfo,供后续切源（只属于本曲目）。
      var idx = 0;
      final firstPerSource = <Source, SongInfo>{};
      final candidates = _songBySourceId.putIfAbsent(
        songKey,
        () => <String, SongInfo>{},
      );
      for (final song in results) {
        final key = _sourceKey(song, idx);
        candidates[key] = song;
        firstPerSource.putIfAbsent(song.source, () => song);
        idx++;
        sources.add(
          LyricSource(
            id: key,
            name: '${song.source.label} - ${song.artistTitle()}',
          ),
        );
      }
      debugPrint('[LyricsService] prefetched sources: ${sources.length}');

      // 2) 对每个 source 各调一次 fetchLyrics (内部已包含全 provider 兜底),
      //    命中 verbatim 即提前结束;全部失败则取首个 lineByLine。
      //    不传 durationMs：候选 SongInfo 自带平台侧时长，用它匹配平台歌词
      //    才准；B 站视频时长常被片头片尾拉偏超过匹配容差，传进去会把
      //    候选全部过滤掉。
      Lyrics? picked;
      String? pickedKey;
      for (final entry in firstPerSource.entries) {
        final song = entry.value;
        Lyrics? lyrics;
        try {
          lyrics = await finder.fetchLyrics(song: song);
        } catch (_) {
          continue;
        }
        if (lyrics == null) continue;

        final origType = lyrics.types[TrackNames.orig];
        // 找到对应的 sourceId
        final matchingKey = _matchSourceId(songKey, song);
        if (matchingKey == null) continue;

        if (origType == LyricsType.verbatim) {
          autoPayload = _buildPayload(
            lyrics,
            sourceId: matchingKey,
            songKey: songKey,
          );
          break;
        } else if (origType == LyricsType.lineByLine) {
          picked = lyrics;
          pickedKey = matchingKey;
          // 继续尝试其他 source,可能后续能找到 verbatim
        }
      }

      autoPayload ??= (picked != null && pickedKey != null)
          ? _buildPayload(picked, sourceId: pickedKey, songKey: songKey)
          : null;

      _sourcesMem[songKey] = sources;
      if (autoPayload != null) {
        _payloadMem[songKey] = autoPayload;
        _failedAt.remove(songKey);
        // 先落盘再 notify：notify 触发的 rebuild 会立刻回来读缓存，
        // fire-and-forget 写入抢不过那次读盘，等于白搜一轮。
        await _writeAutoPayloadCache(music, autoPayload);
      }
      await _writeSourcesCache(music, sources);
    } catch (e) {
      debugPrint('[LyricsService] prefetch failed: $e');
      if (sources.isEmpty) sources.add(localOption);
      _sourcesMem[songKey] = sources;
    }
    if (autoPayload == null) {
      // 没拿到歌词：进入冷却，阻断 notify → rebuild → 再搜索的风暴
      _failedAt[songKey] = DateTime.now();
    }
    debugPrint('[LyricsService] prefetched: ${music.title} - ${music.artist}');
    notifyListeners();
    return LyricsResult(sources: sources, autoPayload: autoPayload);
  }

  /// 某首曲目的候选表(可能为空)。
  Map<String, SongInfo> _candidatesOf(String songKey) =>
      _songBySourceId[songKey] ?? const <String, SongInfo>{};

  /// 在本曲目的候选表里找 [song] 对应的 sourceId。
  String? _matchSourceId(String songKey, SongInfo song) {
    final candidates = _songBySourceId[songKey];
    if (candidates == null) return null;
    final id = song.id;
    final mid = song.mid;
    final hash = song.hash;
    for (final entry in candidates.entries) {
      final s = entry.value;
      if (s.source != song.source) continue;
      if ((id != null && s.id == id) ||
          (mid != null && s.mid == mid) ||
          (hash != null && s.hash == hash)) {
        return entry.key;
      }
    }
    return null;
  }

  // ==================== 缓存清理 ====================

  /// 清空歌词缓存（磁盘 + 内存），供设置页「数据管理」的入口调用。
  ///
  /// 两层都要清：磁盘层决定下次冷启动是否重新联网搜索，内存层
  /// ([_payloadMem] / [_sourcesMem] / [_songBySourceId]) 决定本次会话是否
  /// 重新搜索。失败冷却 ([_failedAt]) 一并清掉，让清完能立刻重试。
  ///
  /// 清完 [notifyListeners]：`lyricsRevisionProvider` 重建 → 当前曲目重新走
  /// 一遍 `lyricsFor` → 缓存已空则重新搜索。因此不拦截仍在途的任务：它们返回
  /// 的是清空之后才拿到的新数据，允许重新写回缓存（否则同一首歌要白搜两轮）。
  Future<void> clearCache() async {
    _payloadMem.clear();
    _sourcesMem.clear();
    _songBySourceId.clear();
    _failedAt.clear();
    // 置空后同一首歌的下一次切歌事件会重新预热
    _prefetchKey = null;
    await cache.emptyCache();
    notifyListeners();
  }

  // ==================== key 与缓存文件 ====================

  /// 曲目唯一键：(bvid, cid)。id 缺失时退化为标题指纹。
  ///
  /// 既是缓存 / in-flight 的 key，也随 [LyricsPayload.songKey] 交给 UI 做
  /// 载荷归属校验；detail_page 等消费方直接调用本静态方法保证一致。
  static String songKeyOf(Music m) {
    if (m.id.isNotEmpty) return '${m.id}:${m.cid}';
    return musicIdentityOf(m);
  }

  /// 与分P无关的曲目身份：bvid；id 缺失时退化为标题指纹。
  ///
  /// 给「手动歌词来源」的作用域判定用（`LyricSelection`）：曲中 `ensureCid`
  /// 回填 cid 会让 [songKeyOf] 变（`BV1xx:` → `BV1xx:12345`），但曲目身份
  /// 不该跟着变，否则用户刚选的来源会在回填那一刻失效。
  static String musicIdentityOf(Music m) {
    if (m.id.isNotEmpty) return m.id;
    return 't:${m.title}|${m.artist}|${m.duration?.inSeconds ?? 0}';
  }

  String _sourceKey(SongInfo song, int index) {
    final id = song.id ?? song.mid ?? song.hash;
    if (id != null) return '${song.source.name}:$id';
    return '${song.source.name}:$index';
  }

  String _payloadCacheKey(Music m) => 'lyrics:payload:${songKeyOf(m)}';
  String _sourcesCacheKey(Music m) => 'lyrics:sources:${songKeyOf(m)}';

  /// 手动选源的载荷缓存 key。
  String _sourceCacheKey(Music m, String sourceId) =>
      'lyrics:src2:${songKeyOf(m)}:$sourceId';

  Future<LyricsPayload?> _readAutoPayloadCache(Music music) async {
    try {
      final info = await cache.getFileFromCache(_payloadCacheKey(music));
      if (info == null) return null;
      final file = info.file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final payload = _decodePayload(raw);
      // 旧版本缓存没有 songKey 字段，按读取目标补戳
      if (payload != null && payload.songKey.isEmpty) {
        return LyricsPayload(
          sourceId: payload.sourceId,
          mainModel: payload.mainModel,
          offsetMs: payload.offsetMs,
          songKey: songKeyOf(music),
        );
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeAutoPayloadCache(
    Music music,
    LyricsPayload payload,
  ) async {
    try {
      final raw = jsonEncode(_encodePayload(payload));
      final bytes = Uint8List.fromList(utf8.encode(raw));
      await cache.putFile(
        _payloadCacheKey(music),
        bytes,
        fileExtension: 'json',
      );
    } catch (e) {
      debugPrint('[LyricsService] write payload cache failed: $e');
    }
  }

  Future<LyricsPayload?> _readPayloadCacheFile(
    Music music,
    String sourceId,
  ) async {
    try {
      final info = await cache.getFileFromCache(
        _sourceCacheKey(music, sourceId),
      );
      if (info == null) return null;
      final file = info.file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final payload = _decodePayload(raw);
      // 旧版本缓存没有 songKey 字段，按读取目标补戳
      if (payload != null && payload.songKey.isEmpty) {
        return LyricsPayload(
          sourceId: payload.sourceId,
          mainModel: payload.mainModel,
          offsetMs: payload.offsetMs,
          songKey: songKeyOf(music),
        );
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePayloadCacheFile(
    Music music,
    String sourceId,
    LyricsPayload payload,
  ) async {
    try {
      final raw = jsonEncode(_encodePayload(payload));
      final bytes = Uint8List.fromList(utf8.encode(raw));
      await cache.putFile(
        _sourceCacheKey(music, sourceId),
        bytes,
        fileExtension: 'json',
      );
    } catch (e) {
      debugPrint('[LyricsService] write per-source cache failed: $e');
    }
  }

  Future<List<LyricSource>?> _readSourcesCache(Music music) async {
    try {
      final info = await cache.getFileFromCache(_sourcesCacheKey(music));
      if (info == null) return null;
      final file = info.file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List).cast<Object?>();
      return [
        for (final entry in list.whereType<Map>())
          LyricSource(
            id: entry['id']?.toString() ?? '',
            name: entry['name']?.toString() ?? '',
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSourcesCache(
    Music music,
    List<LyricSource> sources,
  ) async {
    try {
      final raw = jsonEncode([
        for (final s in sources) {'id': s.id, 'name': s.name},
      ]);
      final bytes = Uint8List.fromList(utf8.encode(raw));
      await cache.putFile(
        _sourcesCacheKey(music),
        bytes,
        fileExtension: 'json',
      );
    } catch (e) {
      debugPrint('[LyricsService] write sources cache failed: $e');
    }
  }

  // ==================== Payload 序列化 ====================

  Map<String, Object?> _encodePayload(LyricsPayload payload) {
    return {
      'sourceId': payload.sourceId,
      'offsetMs': payload.offsetMs,
      'songKey': payload.songKey,
      'model': _encodeModel(payload.mainModel),
    };
  }

  LyricsPayload? _decodePayload(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      final modelJson = map['model'];
      if (modelJson is! Map) return null;
      final model = _decodeModel(modelJson.cast<String, Object?>());
      return LyricsPayload(
        sourceId: map['sourceId']?.toString() ?? '',
        offsetMs: (map['offsetMs'] as num?)?.toInt() ?? 0,
        songKey: map['songKey']?.toString() ?? '',
        mainModel: model,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _encodeModel(LyricModel model) {
    return {
      'tags': model.idTags,
      'lines': [for (final l in model.lines) _encodeLine(l)],
    };
  }

  LyricModel _decodeModel(Map<String, Object?> json) {
    final tags = (json['tags'] as Map?)?.cast<String, String>() ?? const {};
    final rawLines = (json['lines'] as List?) ?? const [];
    final lines = <LyricLine>[
      for (final l in rawLines.whereType<Map>())
        _decodeLine(l.cast<String, Object?>()),
    ];
    return LyricModel(tags: Map<String, String>.from(tags), lines: lines);
  }

  Map<String, Object?> _encodeLine(LyricLine line) {
    return {
      'start': line.start.inMilliseconds,
      if (line.end != null) 'end': line.end!.inMilliseconds,
      'text': line.text,
      'words': [
        for (final w in line.words ?? const <LyricWord>[]) _encodeWord(w),
      ],
      if (line.translation != null) 'translation': line.translation,
    };
  }

  LyricLine _decodeLine(Map<String, Object?> json) {
    return LyricLine(
      start: Duration(milliseconds: (json['start'] as num?)?.toInt() ?? 0),
      end: (json['end'] as num?) == null
          ? null
          : Duration(milliseconds: (json['end'] as num).toInt()),
      text: json['text']?.toString() ?? '',
      words: [
        for (final w in ((json['words'] as List?) ?? const []).whereType<Map>())
          _decodeWord(w.cast<String, Object?>()),
      ],
      translation: json['translation'] as String?,
    );
  }

  Map<String, Object?> _encodeWord(LyricWord word) {
    return {
      'start': word.start.inMilliseconds,
      if (word.end != null) 'end': word.end!.inMilliseconds,
      'text': word.text,
    };
  }

  LyricWord _decodeWord(Map<String, Object?> json) {
    return LyricWord(
      text: json['text']?.toString() ?? '',
      start: Duration(milliseconds: (json['start'] as num?)?.toInt() ?? 0),
      end: (json['end'] as num?) == null
          ? null
          : Duration(milliseconds: (json['end'] as num).toInt()),
    );
  }

  // ==================== LyricModel 构造 ====================

  LyricsPayload _buildPayload(
    Lyrics lyrics, {
    required String sourceId,
    required String songKey,
  }) {
    final shifted = lyrics.addOffset(0);
    final fs = shifted.toFullTimestamp(durationMs: lyrics.inferredDuration);
    final model = _toFlutterLyricModel(fs);
    return LyricsPayload(
      sourceId: sourceId,
      mainModel: model,
      songKey: songKey,
    );
  }

  LyricModel _toFlutterLyricModel(FSLyrics lyrics) {
    final orig = lyrics[TrackNames.orig];
    final ts = lyrics[TrackNames.ts];
    if (orig == null) return LyricModel(lines: const []);

    final lines = <LyricLine>[];
    for (var i = 0; i < orig.length; i++) {
      final ol = orig[i];
      final tl = (ts != null && i < ts.length) ? ts[i] : null;
      final words = ol.words
          .map(
            (w) => LyricWord(
              text: w.text,
              start: w.startDuration,
              end: w.endDuration,
            ),
          )
          .toList(growable: false);
      lines.add(
        LyricLine(
          start: ol.startDuration,
          end: ol.endDuration,
          text: ol.text,
          words: words,
          translation: (tl != null && tl.text.isNotEmpty) ? tl.text : null,
        ),
      );
    }

    return LyricModel(
      tags: Map<String, String>.from(lyrics.tags),
      lines: lines,
    );
  }
}
