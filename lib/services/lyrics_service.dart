import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_lyric/core/lyric_model.dart';

import 'package:lyrics_now/lyrics_now.dart';

import 'package:bilimusic/components/lyric/lyric_source.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/player_coordinator.dart';

/// 已解析的歌词载荷 —— 直接喂给 [LyricController.loadLyricModel]。
class LyricsPayload {
  const LyricsPayload({
    required this.sourceId,
    required this.mainModel,
    this.offsetMs = 0,
  });

  /// 当前选中的歌词来源 id，与 [LyricSource.id] 对应。
  final String sourceId;

  /// 已转成 flutter_lyric [LyricModel] 的歌词主体,带 ts / roma 翻译。
  final LyricModel mainModel;

  /// 歌词偏移,毫秒。
  final int offsetMs;
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

  // 内存层缓存 (避免每次都读盘)
  final Map<String, LyricsPayload> _payloadMem = {};
  final Map<String, List<LyricSource>> _sourcesMem = {};
  final Map<String, SongInfo> _songBySourceId = {};

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
    final key = _songKey(music);
    if (key == _prefetchKey) return;
    _prefetchKey = key;
    // fire-and-forget:错误被内部吞掉,不会影响 UI
    unawaited(prefetch(music));
  }

  // ==================== 公开 API ====================

  /// 同步返回当前已知的来源列表 (缓存 miss 时为空)。
  List<LyricSource> sourcesFor(Music music) {
    return _sourcesMem[_songKey(music)] ?? const <LyricSource>[];
  }

  /// 异步获取 (或返回缓存) 当前歌曲的主歌词载荷。
  Future<LyricsPayload?> lyricsFor(Music music) async {
    final result = await prefetch(music);
    return result?.autoPayload;
  }

  /// 切换歌词来源 —— 已缓存直接返回;未缓存通过 [LyricFinder.fetchLyrics]
  /// 走单一来源(节省旧实现对全部候选串行重试的开销)。
  Future<LyricsPayload?> fetchBySourceId(String sourceId, Music music) async {
    if (sourceId == 'local') return null;

    final songKey = _songKey(music);
    final inflightKey = '$songKey::$sourceId';
    final pending = _inFlightSource[inflightKey];
    if (pending != null) return pending;

    // 命中已缓存的 payload
    final mem = _payloadMem[inflightKey];
    if (mem != null) return mem;
    final cached = await _readPayloadCacheFile(music, sourceId);
    if (cached != null) {
      _payloadMem[inflightKey] = cached;
      return cached;
    }

    final song = _songBySourceId[sourceId];
    if (song == null) {
      // 没有该来源的 SongInfo,需要先完整预热一次
      await prefetch(music);
      final after = _songBySourceId[sourceId];
      if (after == null) return null;
      return _fetchAndCacheBySource(sourceId, after, music, inflightKey);
    }
    return _fetchAndCacheBySource(sourceId, song, music, inflightKey);
  }

  Future<LyricsPayload?> _fetchAndCacheBySource(
    String sourceId,
    SongInfo song,
    Music music,
    String inflightKey,
  ) async {
    final future = _doFetchBySource(sourceId, song, music).whenComplete(() {
      _inFlightSource.remove(inflightKey);
    });
    _inFlightSource[inflightKey] = future;
    return future;
  }

  Future<LyricsPayload?> _doFetchBySource(
    String sourceId,
    SongInfo song,
    Music music,
  ) async {
    try {
      final lyrics = await finder.fetchLyrics(song: song);
      if (lyrics == null) return null;
      final payload = _buildPayload(lyrics, sourceId: sourceId);
      _payloadMem['${_songKey(music)}::$sourceId'] = payload;
      unawaited(_writePayloadCacheFile(music, sourceId, payload));
      notifyListeners();
      return payload;
    } catch (e) {
      debugPrint('[LyricsService] fetchBySourceId failed: $e');
      return null;
    }
  }

  /// 后台预热:搜索 + 单次 `fetchLyrics` + 写缓存。
  Future<LyricsResult?> prefetch(Music music) async {
    final songKey = _songKey(music);
    final pending = _inFlightResult[songKey];
    if (pending != null) return pending;

    // 1) 读 payload + sources 缓存(双文件)
    final cachedPayload = await _readAutoPayloadCache(music);
    final cachedSources = await _readSourcesCache(music);

    if (cachedPayload != null) {
      _payloadMem[songKey] = cachedPayload;
      if (cachedSources != null) _sourcesMem[songKey] = cachedSources;
      return LyricsResult(
        sources: cachedSources ?? const [LyricSource(id: 'local', name: '')],
        autoPayload: cachedPayload,
      );
    }

    final future = _doPrefetch(music, songKey).whenComplete(() {
      _inFlightResult.remove(songKey);
    });
    _inFlightResult[songKey] = future;
    return future;
  }

  Future<LyricsResult?> _doPrefetch(Music music, String songKey) async {
    final durationMs = music.duration?.inMilliseconds ?? 0;
    final localOption = LyricSource(id: 'local', name: music.title);
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

      // 记录每条候选的 SongInfo,供后续切源。
      var idx = 0;
      final firstPerSource = <Source, SongInfo>{};
      for (final song in results) {
        final key = _sourceKey(song, idx);
        _songBySourceId[key] = song;
        firstPerSource.putIfAbsent(song.source, () => song);
        idx++;
        sources.add(
          LyricSource(id: key, name: '${song.source.label} - ${song.artistTitle()}'),
        );
      }
      debugPrint('[LyricsService] prefetched sources: ${sources.length}');

      // 2) 对每个 source 各调一次 fetchLyrics (内部已包含全 provider 兜底),
      //    命中 verbatim 即提前结束;全部失败则取首个 lineByLine。
      Lyrics? picked;
      String? pickedKey;
      for (final entry in firstPerSource.entries) {
        final song = entry.value;
        Lyrics? lyrics;
        try {
          lyrics = await finder.fetchLyrics(
            song: song,
            durationMs: durationMs,
          );
        } catch (_) {
          continue;
        }
        if (lyrics == null) continue;

        final origType = lyrics.types[TrackNames.orig];
        // 找到对应的 sourceId
        final matchingKey = _matchSourceId(song);
        if (matchingKey == null) continue;

        if (origType == LyricsType.verbatim) {
          autoPayload = _buildPayload(lyrics, sourceId: matchingKey);
          break;
        } else if (origType == LyricsType.lineByLine) {
          picked = lyrics;
          pickedKey = matchingKey;
          // 继续尝试其他 source,可能后续能找到 verbatim
        }
      }

      autoPayload ??= (picked != null && pickedKey != null)
          ? _buildPayload(picked, sourceId: pickedKey)
          : null;

      _sourcesMem[songKey] = sources;
      if (autoPayload != null) {
        _payloadMem[songKey] = autoPayload;
        unawaited(_writeAutoPayloadCache(music, autoPayload));
      }
      unawaited(_writeSourcesCache(music, sources));
    } catch (e) {
      debugPrint('[LyricsService] prefetch failed: $e');
      if (sources.isEmpty) sources.add(localOption);
      _sourcesMem[songKey] = sources;
    }
    debugPrint('[LyricsService] prefetched: ${music.title} - ${music.artist}');
    notifyListeners();
    return LyricsResult(sources: sources, autoPayload: autoPayload);
  }

  String? _matchSourceId(SongInfo song) {
    final id = song.id;
    final mid = song.mid;
    final hash = song.hash;
    for (final entry in _songBySourceId.entries) {
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

  // ==================== key 与缓存文件 ====================

  String _songKey(Music m) {
    if (m.id.isNotEmpty) return '${m.id}:${m.cid}';
    return 't:${m.title}|${m.artist}|${m.duration?.inSeconds ?? 0}';
  }

  String _sourceKey(SongInfo song, int index) {
    final id = song.id ?? song.mid ?? song.hash;
    if (id != null) return '${song.source.name}:$id';
    return '${song.source.name}:$index';
  }

  String _payloadCacheKey(Music m) => 'lyrics:payload:${_songKey(m)}';
  String _sourcesCacheKey(Music m) => 'lyrics:sources:${_songKey(m)}';
  String _sourceCacheKey(Music m, String sourceId) =>
      'lyrics:src:${_songKey(m)}:$sourceId';

  Future<LyricsPayload?> _readAutoPayloadCache(Music music) async {
    try {
      final info = await cache.getFileFromCache(_payloadCacheKey(music));
      if (info == null) return null;
      final file = info.file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return _decodePayload(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeAutoPayloadCache(Music music, LyricsPayload payload) async {
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

  Future<LyricsPayload?> _readPayloadCacheFile(Music music, String sourceId) async {
    try {
      final info = await cache.getFileFromCache(_sourceCacheKey(music, sourceId));
      if (info == null) return null;
      final file = info.file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return _decodePayload(raw);
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

  Future<void> _writeSourcesCache(Music music, List<LyricSource> sources) async {
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
      start: Duration(
        milliseconds: (json['start'] as num?)?.toInt() ?? 0,
      ),
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
      start: Duration(
        milliseconds: (json['start'] as num?)?.toInt() ?? 0,
      ),
      end: (json['end'] as num?) == null
          ? null
          : Duration(milliseconds: (json['end'] as num).toInt()),
    );
  }

  // ==================== LyricModel 构造 ====================

  LyricsPayload _buildPayload(Lyrics lyrics, {required String sourceId}) {
    final shifted = lyrics.addOffset(0);
    final fs = shifted.toFullTimestamp(durationMs: lyrics.inferredDuration);
    final model = _toFlutterLyricModel(fs);
    return LyricsPayload(sourceId: sourceId, mainModel: model);
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