import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:snownlp/snownlp.dart' as snow;
import 'package:snownlp/snownlp_flutter.dart' show FlutterAssetLoader;

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';
import 'package:bilimusic/features/taste/logic/profile_ranker.dart';

/// snownlp 的常驻 worker isolate。
///
/// 生命周期：首次请求时拉起；连续 [idleTimeout] 没有请求就退出，模型内存随
/// 隔离堆一起回收；下次请求重新拉起。worker 异常退出时在飞请求全部失败，
/// 下一次请求会重新拉起，调用方各自降级（重排跳过 / 漫游退回 simhash）。
class TasteWorker {
  TasteWorker({
    this.idleTimeout = defaultIdleTimeout,
    TasteSegmenter? segmenter,
    StopwordFilter? stopFilter,
  }) : _segmenter = segmenter,
       _stopFilter = stopFilter;

  /// 空闲退出时间。
  static const Duration defaultIdleTimeout = Duration(minutes: 10);

  final Duration idleTimeout;

  /// 测试注入：分词器 / 停用词过滤，必须能跨 isolate 传递（顶层函数）。
  /// 两者都注入时 worker 完全不读模型资产。
  final TasteSegmenter? _segmenter;
  final StopwordFilter? _stopFilter;

  _WorkerHandle? _handle;
  Future<_WorkerHandle>? _starting;
  Timer? _idleTimer;
  int _inFlight = 0;
  int _spawnCount = 0;
  bool _disposed = false;

  /// worker 当前是否在线（诊断 / 测试用）。
  bool get isActive => _handle != null;

  /// 累计拉起次数（测试用）。
  @visibleForTesting
  int get spawnCount => _spawnCount;

  /// 在 worker 里构建画像；参数与 [TasteProfileBuilder.build] 对齐。
  Future<TasteProfile> buildProfile(
    List<ProfileSample> samples, {
    List<String> forcedTexts = const [],
    int topN = 48,
    int maxEdgesPerNode = 5,
    double forcedBoost = 2.5,
    DateTime? now,
  }) async {
    final updatedAt = now ?? DateTime.now();
    if (samples.isEmpty && forcedTexts.isEmpty) {
      // 与 [TasteProfileBuilder.build] 的短路一致：没有样本就不为一次
      // 空构建拉起 isolate、读模型字节。
      return TasteProfile(updatedAt: updatedAt);
    }
    final result = await _request(
      _Request.buildProfile(
        samples: samples,
        forcedTexts: forcedTexts,
        topN: topN,
        maxEdgesPerNode: maxEdgesPerNode,
        forcedBoost: forcedBoost,
        updatedAtMs: updatedAt.millisecondsSinceEpoch,
      ),
    );
    return result as TasteProfile;
  }

  /// 批量口味分：[Music.key] → (0, 1+]。
  ///
  /// 空候选 / 空画像直接返回空表，不为一次空操作拉起 worker。
  Future<Map<String, double>> scoreTracks(
    List<Music> items,
    TasteProfile profile,
  ) async {
    if (items.isEmpty || profile.isEmpty) return const {};
    final result = await _request(
      _Request.scoreTracks(items: items, profile: profile),
    );
    return Map<String, double>.from(result as Map);
  }

  /// 释放 worker 并取消空闲计时。之后的请求会抛 [StateError]。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    final handle = _handle;
    _handle = null;
    handle?.close();
  }

  Future<Object?> _request(_Request request) async {
    if (_disposed) throw StateError('TasteWorker 已释放');
    _idleTimer?.cancel();
    _inFlight++;
    try {
      final handle = await _ensureHandle();
      return await handle.request(request);
    } finally {
      _inFlight--;
      _armIdleTimer();
    }
  }

  Future<_WorkerHandle> _ensureHandle() {
    final handle = _handle;
    if (handle != null) return Future.value(handle);
    return _starting ??= _start();
  }

  Future<_WorkerHandle> _start() async {
    try {
      final modelBytes = await _loadModelBytes();
      final handle = _WorkerHandle(_onHandleClosed);
      try {
        await handle.start(
          modelBytes: modelBytes,
          segmenter: _segmenter,
          stopFilter: _stopFilter,
        );
      } catch (_) {
        handle.close();
        rethrow;
      }
      if (_disposed) {
        // 拉起期间被 Provider 释放：不能把 worker 留在后台。
        handle.close();
        throw StateError('TasteWorker 已释放');
      }
      _handle = handle;
      _spawnCount++;
      return handle;
    } finally {
      _starting = null;
    }
  }

  void _onHandleClosed(_WorkerHandle handle) {
    if (identical(_handle, handle)) _handle = null;
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_disposed || _inFlight > 0 || _handle == null) return;
    _idleTimer = Timer(idleTimeout, _retireIdleWorker);
  }

  void _retireIdleWorker() {
    _idleTimer = null;
    if (_inFlight > 0) return;
    final handle = _handle;
    _handle = null;
    handle?.close();
  }

  Future<Map<String, Uint8List>> _loadModelBytes() async {
    // 两端都注入时 worker 完全不碰模型，不必读资产。
    if (_segmenter != null && _stopFilter != null) return const {};
    final loader = FlutterAssetLoader();
    return {
      'seg.bin': await loader.loadBytes('seg.bin'),
      'stopwords.bin': await loader.loadBytes('stopwords.bin'),
    };
  }
}

/// 主 isolate 侧的 worker 句柄：请求编号 → 响应分发、错误/退出兜底。
class _WorkerHandle {
  _WorkerHandle(this._onClosed) {
    _ready.listen(_handleMessage);
    _errors.listen(_handleError);
    _exits.listen(_handleExit);
  }

  final void Function(_WorkerHandle) _onClosed;

  /// 单次请求上限：模型解压 + 一批分词远低于这个量级，超时视为 worker 卡死。
  static const Duration _requestTimeout = Duration(seconds: 60);

  final ReceivePort _ready = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final ReceivePort _exits = ReceivePort();
  final Completer<SendPort> _handshake = Completer<SendPort>();
  final Map<int, Completer<Object?>> _pending = {};

  Isolate? _isolate;
  SendPort? _sendPort;
  int _nextId = 1;
  bool _closed = false;

  Future<void> start({
    required Map<String, Uint8List> modelBytes,
    required TasteSegmenter? segmenter,
    required StopwordFilter? stopFilter,
  }) async {
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        _WorkerBootstrap(
          parent: _ready.sendPort,
          modelBytes: modelBytes,
          segmenter: segmenter,
          stopFilter: stopFilter,
        ),
        debugName: 'taste-worker',
        onError: _errors.sendPort,
        onExit: _exits.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      _shutdown();
      rethrow;
    }

    try {
      _sendPort = await _handshake.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      _shutdown();
      rethrow;
    }
  }

  Future<Object?> request(_Request request) {
    final sendPort = _sendPort;
    if (sendPort == null || _closed) {
      return Future<Object?>.error(StateError('taste worker 未就绪'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    sendPort.send(_Job(id, request));
    // 兜底：worker 在退出事件送达前死掉时，SendPort 会静默丢消息，
    // 不设超时调用方就会永远等在 future 上。
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        final error = TimeoutException('taste worker 请求超时', _requestTimeout);
        _failPending(error);
        _shutdown();
        throw error;
      },
    );
  }

  void close() {
    if (_closed) return;
    _failPending(StateError('taste worker 已关闭'));
    _shutdown();
  }

  void _handleMessage(Object? message) {
    if (message is SendPort) {
      if (!_handshake.isCompleted) _handshake.complete(message);
      return;
    }
    if (message is! _WorkerResponse) return;
    final completer = _pending.remove(message.id);
    if (completer == null || completer.isCompleted) return;
    if (message.error != null) {
      completer.completeError(
        StateError('taste worker: ${message.error}'),
        StackTrace.fromString(message.stack ?? ''),
      );
    } else {
      completer.complete(message.result);
    }
  }

  void _handleError(Object? message) {
    final detail = message is List && message.isNotEmpty
        ? message.first
        : message;
    final error = StateError('taste worker 崩溃: $detail');
    if (!_handshake.isCompleted) _handshake.completeError(error);
    _failPending(error);
    _shutdown();
  }

  void _handleExit(Object? _) {
    final error = StateError('taste worker 已退出');
    if (!_handshake.isCompleted) _handshake.completeError(error);
    _failPending(error);
    _shutdown();
  }

  void _shutdown() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _closePorts();
    _onClosed(this);
  }

  void _failPending(Object error) {
    if (_pending.isEmpty) return;
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  void _closePorts() {
    _ready.close();
    _errors.close();
    _exits.close();
  }
}

/// worker isolate 入口；只通过端口收发消息，不接触 UI / 平台通道。
void _workerMain(_WorkerBootstrap bootstrap) {
  final port = ReceivePort();
  bootstrap.parent.send(port.sendPort);

  if (bootstrap.modelBytes.isNotEmpty) {
    snow.SnowConfig.instance.assetLoader = _ModelBytesLoader(
      bootstrap.modelBytes,
    );
  }

  final segmenter = bootstrap.segmenter ?? TasteProfileBuilder.defaultSegmenter;
  final injectedStopFilter = bootstrap.stopFilter;
  final stopFilter = injectedStopFilter != null
      ? Future<StopwordFilter>.value(injectedStopFilter)
      : TasteProfileBuilder.defaultStopFilter();

  port.listen((message) async {
    if (message is! _Job) return;
    try {
      final result = await _dispatch(
        message.request,
        segmenter: segmenter,
        stopFilter: stopFilter,
      );
      bootstrap.parent.send(_WorkerResponse(id: message.id, result: result));
    } catch (e, stack) {
      bootstrap.parent.send(
        _WorkerResponse(id: message.id, error: '$e', stack: '$stack'),
      );
    }
  });
}

Future<Object?> _dispatch(
  _Request request, {
  required TasteSegmenter segmenter,
  required Future<StopwordFilter> stopFilter,
}) async {
  switch (request.op) {
    case _WorkerOp.buildProfile:
      final builder = TasteProfileBuilder(
        segmenter: segmenter,
        stopFilter: await stopFilter,
      );
      return builder.build(
        request.samples,
        forcedTexts: request.forcedTexts,
        topN: request.topN,
        maxEdgesPerNode: request.maxEdgesPerNode,
        forcedBoost: request.forcedBoost,
        now: DateTime.fromMillisecondsSinceEpoch(request.updatedAtMs),
      );
    case _WorkerOp.scoreTracks:
      final profile = request.profile;
      if (profile == null) {
        throw StateError('scoreTracks 缺少画像');
      }
      return tasteScoresFor(
        request.items,
        profile,
        segmenter: segmenter,
        stopFilter: await stopFilter,
      );
  }
}

enum _WorkerOp { buildProfile, scoreTracks }

/// 一次请求：只放可跨 isolate 传递的值。
class _Request {
  const _Request({
    required this.op,
    this.samples = const [],
    this.forcedTexts = const [],
    this.topN = 48,
    this.maxEdgesPerNode = 5,
    this.forcedBoost = 2.5,
    this.updatedAtMs = 0,
    this.items = const [],
    this.profile,
  });

  factory _Request.buildProfile({
    required List<ProfileSample> samples,
    required List<String> forcedTexts,
    required int topN,
    required int maxEdgesPerNode,
    required double forcedBoost,
    required int updatedAtMs,
  }) => _Request(
    op: _WorkerOp.buildProfile,
    samples: samples,
    forcedTexts: forcedTexts,
    topN: topN,
    maxEdgesPerNode: maxEdgesPerNode,
    forcedBoost: forcedBoost,
    updatedAtMs: updatedAtMs,
  );

  factory _Request.scoreTracks({
    required List<Music> items,
    required TasteProfile profile,
  }) => _Request(op: _WorkerOp.scoreTracks, items: items, profile: profile);

  final _WorkerOp op;
  final List<ProfileSample> samples;
  final List<String> forcedTexts;
  final int topN;
  final int maxEdgesPerNode;
  final double forcedBoost;
  final int updatedAtMs;
  final List<Music> items;
  final TasteProfile? profile;
}

class _Job {
  const _Job(this.id, this.request);

  final int id;
  final _Request request;
}

class _WorkerResponse {
  const _WorkerResponse({
    required this.id,
    this.result,
    this.error,
    this.stack,
  });

  final int id;
  final Object? result;
  final String? error;
  final String? stack;
}

class _WorkerBootstrap {
  const _WorkerBootstrap({
    required this.parent,
    required this.modelBytes,
    required this.segmenter,
    required this.stopFilter,
  });

  final SendPort parent;
  final Map<String, Uint8List> modelBytes;
  final TasteSegmenter? segmenter;
  final StopwordFilter? stopFilter;
}

/// worker 内的资产加载器：直接返回主 isolate 预读的模型字节，避免后台
/// isolate 访问 `rootBundle`（那需要额外的平台消息注册）。
class _ModelBytesLoader extends FlutterAssetLoader {
  _ModelBytesLoader(this._bytes);

  final Map<String, Uint8List> _bytes;

  @override
  Future<Uint8List> loadBytes(String name) async {
    final bytes = _bytes[name];
    if (bytes == null) {
      throw StateError('snownlp: 缺少模型字节 $name');
    }
    return bytes;
  }
}
