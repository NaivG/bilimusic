import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'package:bilimusic/models/sync/lan_sync_mode.dart';
import 'package:bilimusic/models/sync/peer_device.dart';
import 'package:bilimusic/services/sync/device_identity.dart';
import 'package:bilimusic/utils/platform_helper.dart';

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
/// Web 平台无 mDNS；[start] 在 [PlatformHelper.isWeb] 下静默 no-op。
class MdnsService {
  static const String serviceType = '_bilimusic-sync._tcp';
  static const int defaultPort = 47890;
  static const String _version = '2';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  DeviceIdentity? _identity;
  int _port = defaultPort;
  LanSyncMode _mode = LanSyncMode.off;

  final _peersController = StreamController<PeerDevice>.broadcast();
  final _lostController = StreamController<String>.broadcast();

  /// 新发现 / 解析完成 / TXT 更新的对端。
  Stream<PeerDevice> get peerStream => _peersController.stream;

  /// 对端消失事件，参数为对端 id。
  Stream<String> get lostStream => _lostController.stream;

  bool get isActive => _broadcast != null || _discovery != null;

  /// 启动广播 + 浏览。
  ///
  /// [mode] == off 时直接 [stop] 返回。重复调用且配置未变则 no-op。
  Future<void> start({
    required DeviceIdentity identity,
    required LanSyncMode mode,
    int port = defaultPort,
  }) async {
    if (PlatformHelper.isWeb) return;

    if (mode == LanSyncMode.off) {
      await stop();
      return;
    }

    if (isActive &&
        _identity?.id == identity.id &&
        _port == port &&
        _mode == mode) {
      return;
    }

    await stop();

    _identity = identity;
    _port = port;
    _mode = mode;

    await _startBroadcast(identity, port, mode);
    await _startDiscovery();
  }

  Future<void> _startBroadcast(
    DeviceIdentity identity,
    int port,
    LanSyncMode mode,
  ) async {
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
    final broadcast = BonsoirBroadcast(service: service);
    try {
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MdnsService: broadcast start failed: $e');
      }
    }
  }

  Future<void> _startDiscovery() async {
    final discovery = BonsoirDiscovery(type: serviceType);
    try {
      await discovery.initialize();
      _discovery = discovery;
      _discoverySub = discovery.eventStream?.listen(
        (event) => _onDiscoveryEvent(discovery, event),
      );
      await discovery.start();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MdnsService: discovery start failed: $e');
      }
    }
  }

  void _onDiscoveryEvent(
    BonsoirDiscovery discovery,
    BonsoirDiscoveryEvent event,
  ) {
    final service = event.service;
    if (service == null) return;

    if ((event is BonsoirDiscoveryServiceFoundEvent ||
            event is BonsoirDiscoveryServiceUpdatedEvent) &&
        service.hostAddresses.isEmpty) {
      unawaited(service.resolve(discovery.serviceResolver));
      return;
    }

    final id = service.attributes['id'];
    if (id == null || id == _identity?.id) return;

    if (event is BonsoirDiscoveryServiceLostEvent) {
      if (!_lostController.isClosed) _lostController.add(id);
      return;
    }

    if (event is BonsoirDiscoveryServiceFoundEvent ||
        event is BonsoirDiscoveryServiceResolvedEvent ||
        event is BonsoirDiscoveryServiceUpdatedEvent) {
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

  Future<void> stop() async {
    await _discoverySub?.cancel();
    _discoverySub = null;

    if (_broadcast != null) {
      try {
        await _broadcast!.stop();
      } catch (_) {}
      _broadcast = null;
    }
    if (_discovery != null) {
      try {
        await _discovery!.stop();
      } catch (_) {}
      _discovery = null;
    }
  }

  Future<void> dispose() async {
    await stop();
    if (!_peersController.isClosed) await _peersController.close();
    if (!_lostController.isClosed) await _lostController.close();
  }
}
