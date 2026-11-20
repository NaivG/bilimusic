import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/lan_sync/logic/resolve_deduper.dart';
import 'package:bilimusic/features/lan_sync/logic/serial_executor.dart';
import 'package:bilimusic/features/lan_sync/services/device_identity.dart';

/// Bonsoir 包装：mDNS 广播 + 浏览。
///
/// TXT 记录字段（写入）：
///   - `id`：设备 UUID
///   - `name`：用户可见设备名
///   - `platform`：android / windows / macos / linux
///   - `mode`：private / public
///   - `ver`：协议版本，固定 `1`
///
/// 浏览流产出：
///   - [peerStream]：发现 / 解析完成 / 更新时发出 `PeerDevice`
///   - [lostStream]：对端消失时发出对端 id
///
/// 这里给数据竞争做两层纵深防御：
///
/// - `start` / `stop` / `dispose` 全部经 [SerialExecutor] 串行执行，避免原生
///   广播 / 发现对象被并发创建与销毁；
/// - 同一服务的 `resolve` 在途去重，避免 Found / Updated 重复触发并发解析。
class MdnsService {
  static const String serviceType = '_bilimusic-sync._tcp';
  static const int defaultPort = 47890;
  static const String _version = '2';

  /// 生命周期操作串行队列：队内操作依次执行，队外调用永远排队进入。
  final SerialExecutor _lifecycle = SerialExecutor();

  /// 同一服务的解析在途占位。
  final ResolveDeduper _resolveDeduper = ResolveDeduper();

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  DeviceIdentity? _identity;
  int _port = defaultPort;
  LanSyncMode _mode = LanSyncMode.off;

  /// 已释放：之后的 start 不再创建任何原生对象。
  bool _disposed = false;

  /// 正在停止：此间到达的发现事件一律丢弃，避免对即将销毁的 discovery
  /// 再发起 resolve。
  bool _stopping = false;

  final _peersController = StreamController<PeerDevice>.broadcast();
  final _lostController = StreamController<String>.broadcast();

  /// 新发现 / 解析完成 / TXT 更新的对端。
  Stream<PeerDevice> get peerStream => _peersController.stream;

  /// 对端消失事件，参数为对端 id。
  Stream<String> get lostStream => _lostController.stream;

  bool get isActive => _broadcast != null || _discovery != null;

  /// 启动广播 + 浏览。
  ///
  /// [mode] == off 时相当于 [stop]。重复调用且配置未变则 no-op。
  ///
  /// 调用会排进生命周期队列；失败只记调试日志并把内部状态回滚为"未启动"
  /// （原生对象已全部释放），不向调用方抛异常。
  Future<void> start({
    required DeviceIdentity identity,
    required LanSyncMode mode,
    int port = defaultPort,
  }) {
    return _lifecycle.run(
      () => _startInternal(identity: identity, mode: mode, port: port),
    );
  }

  /// 停止广播 + 浏览并释放原生对象，排进生命周期队列依次执行。
  Future<void> stop() => _lifecycle.run(_stopInternal);

  /// 停止并关闭所有事件流。释放后 [start] 不再生效。
  Future<void> dispose() => _lifecycle.run(_disposeInternal);

  Future<void> _disposeInternal() async {
    if (_disposed) return;
    _disposed = true;
    await _stopInternal();
    if (!_peersController.isClosed) await _peersController.close();
    if (!_lostController.isClosed) await _lostController.close();
  }

  Future<void> _startInternal({
    required DeviceIdentity identity,
    required LanSyncMode mode,
    required int port,
  }) async {
    if (_disposed) return;

    if (mode == LanSyncMode.off) {
      await _stopInternal();
      return;
    }

    if (isActive &&
        _identity?.id == identity.id &&
        _port == port &&
        _mode == mode) {
      return;
    }

    // 配置变化或上次启动不完整：先把旧的原生对象彻底销毁再重建。
    await _stopInternal();

    _identity = identity;
    _port = port;
    _mode = mode;

    final broadcastStarted = await _startBroadcast(identity, port, mode);
    final discoveryStarted = await _startDiscovery();
    if (broadcastStarted && discoveryStarted) return;

    // 任一步失败都回滚到"未启动"：否则残留的半套对象会让下一次同配置
    // start 命中上面的 no-op 判断，永远等不到重试。
    if (kDebugMode) {
      debugPrint(
        'MdnsService: start rolled back '
        '(broadcast=$broadcastStarted, discovery=$discoveryStarted)',
      );
    }
    await _stopInternal();
  }

  Future<bool> _startBroadcast(
    DeviceIdentity identity,
    int port,
    LanSyncMode mode,
  ) async {
    BonsoirBroadcast? broadcast;
    try {
      final service = BonsoirService(
        name: identity.name,
        type: serviceType,
        port: port,
        attributes: {
          'id': identity.id,
          'name': identity.name,
          'platform': identity.platform,
          'mode': mode.mdnsValue,
          'ver': _version,
        },
      );
      broadcast = BonsoirBroadcast(service: service);
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MdnsService: broadcast start failed: $e');
      }
      // 初始化/启动到一半的原生对象也要收掉，不能留给下一次 start。
      try {
        await broadcast?.stop();
      } catch (_) {}
      return false;
    }
  }

  Future<bool> _startDiscovery() async {
    final discovery = BonsoirDiscovery(type: serviceType);
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    try {
      await discovery.initialize();
      subscription = discovery.eventStream?.listen(
        (event) => _onDiscoveryEvent(discovery, event),
      );
      await discovery.start();
      _discoverySub = subscription;
      _discovery = discovery;
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MdnsService: discovery start failed: $e');
      }
      await subscription?.cancel();
      try {
        await discovery.stop();
      } catch (_) {}
      return false;
    }
  }

  void _onDiscoveryEvent(
    BonsoirDiscovery discovery,
    BonsoirDiscoveryEvent event,
  ) {
    // 停止过程中到达的事件属于即将销毁的 discovery，不再发起任何原生调用。
    if (_disposed || _stopping) return;

    final service = event.service;
    if (service == null) return;

    final key = _resolveKey(service);

    final isFound = event is BonsoirDiscoveryServiceFoundEvent;
    final isResolved = event is BonsoirDiscoveryServiceResolvedEvent;
    final isUpdated = event is BonsoirDiscoveryServiceUpdatedEvent;
    final isLost = event is BonsoirDiscoveryServiceLostEvent;

    // 终态事件说明这一轮解析有结果了（Lost 时可能没有地址），释放去重占位；
    // Resolved 即使没带地址也释放——对 Resolved 再发 resolve 只会死循环。
    if (isLost ||
        isResolved ||
        (isUpdated && service.hostAddresses.isNotEmpty)) {
      _resolveDeduper.complete(key);
    }

    if ((isFound || isUpdated) && service.hostAddresses.isEmpty) {
      _requestResolve(discovery, service, key);
      return;
    }

    final id = service.attributes['id'];
    if (id == null || id == _identity?.id) return;

    if (isLost) {
      if (!_lostController.isClosed) _lostController.add(id);
      return;
    }

    if (isFound || isResolved || isUpdated) {
      if (service.hostAddresses.isEmpty || service.port <= 0) return;
      final host = InternetAddress.tryParse(service.hostAddresses.first);
      if (host == null) return;
      final peer = PeerDevice(
        id: id,
        name: service.attributes['name'] ?? service.name,
        platform: service.attributes['platform'] ?? 'unknown',
        mode: LanSyncMode.fromString(service.attributes['mode']),
        host: host,
        port: service.port,
        lastSeen: DateTime.now(),
      );
      if (!_peersController.isClosed) _peersController.add(peer);
    }
  }

  /// 发起一次服务解析；同一服务在途期间不再重复发起。
  void _requestResolve(
    BonsoirDiscovery discovery,
    BonsoirService service,
    String key,
  ) {
    if (!_resolveDeduper.tryBegin(key)) return;
    // 解析结果由发现事件流回传，这里不阻塞事件处理；异常必须在
    // [_resolveSafely] 内部消化，不能变成未处理异步异常。
    unawaited(_resolveSafely(discovery, service, key));
  }

  /// 包住 `resolve` 的异步调用：失败只记调试日志，并释放去重占位，
  /// 让后续 Found / Updated 还能重试。
  ///
  /// 成功时**故意不释放**：`resolve` 返回只代表解析请求已提交，真正的地址
  /// 回填与结果通过发现事件流（Resolved / 带地址的 Updated / Lost）异步回传，
  /// 由 [_onDiscoveryEvent] 在终态事件里释放；事件全部丢失时由 5s 超时兜底。
  Future<void> _resolveSafely(
    BonsoirDiscovery discovery,
    BonsoirService service,
    String key,
  ) async {
    try {
      await service.resolve(discovery.serviceResolver);
    } catch (e) {
      _resolveDeduper.complete(key);
      if (kDebugMode) {
        debugPrint('MdnsService: resolve failed: $e');
      }
    }
  }

  /// 解析去重键：同一服务以 (type, name) 唯一标识。
  static String _resolveKey(BonsoirService service) =>
      '${service.type}\u0000${service.name}';

  /// 真正执行停止。只能在生命周期队列内调用（[stop] 负责入队，
  /// [_startInternal] 本身已在队列中）；这样启动流程就能安全复用，
  /// 不会出现"给同一把锁重复加锁"的死锁。
  Future<void> _stopInternal() async {
    _stopping = true;
    try {
      await _discoverySub?.cancel();
      _discoverySub = null;

      // 在途占位属于即将销毁的 discovery，直接丢弃，等新实例重新开始。
      _resolveDeduper.clear();

      // 先摘下字段再 stop：即使原生 stop 抛错，也不会留下一个"看似活着"
      // 的对象导致下一次 start 命中 no-op。
      final broadcast = _broadcast;
      _broadcast = null;
      if (broadcast != null) {
        try {
          await broadcast.stop();
        } catch (_) {}
      }

      final discovery = _discovery;
      _discovery = null;
      if (discovery != null) {
        try {
          await discovery.stop();
        } catch (_) {}
      }

      // 回到"未启动"的配置状态，下一次 start 不会因旧配置误判为 no-op。
      _identity = null;
      _port = defaultPort;
      _mode = LanSyncMode.off;
    } finally {
      _stopping = false;
    }
  }
}
