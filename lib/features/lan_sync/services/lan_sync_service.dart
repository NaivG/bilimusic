import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/lan_sync/models/sync_message.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/lan_sync/services/device_identity.dart';
import 'package:bilimusic/features/lan_sync/services/lan_session.dart';
import 'package:bilimusic/features/lan_sync/services/mdns_service.dart';
import 'package:bilimusic/features/lan_sync/services/pairing_service.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 远端对端推过来的"现在播放"快照。
class RemoteNowPlaying {
  final String peerId;
  final String peerName;
  final Music? music;
  final Duration position;
  final bool isPlaying;
  final List<Music> queue;
  final int currentIndex;

  const RemoteNowPlaying({
    required this.peerId,
    required this.peerName,
    required this.music,
    required this.position,
    required this.isPlaying,
    required this.queue,
    required this.currentIndex,
  });
}

/// UI 收到的 PIN 请求（被动方：对方 hello 触发了需要 PIN）。
class PinRequest {
  final String peerId;
  final String peerName;
  const PinRequest({required this.peerId, required this.peerName});
}

/// 主动方（A）发起配对后的最终结果。
///
/// 通过 [LanSyncService.pairingResults] 流推送给等待对话框。
class PairingResult {
  final String peerId;
  final bool ok;
  final String? reason;
  const PairingResult({required this.peerId, required this.ok, this.reason});
}

/// 顶层服务：装配 mDNS、TCP、ServerSocket、配对、播放器桥接。
///
/// 生命周期由 [start] / [stop] 控制；订阅 [SettingsManager] 的模式变更自动启停
/// mDNS；订阅 [PlayerCoordinator] 的播放状态变化做防抖广播。
class LanSyncService {
  LanSyncService({
    required this.identity,
    required this.pairing,
    required this.settings,
    required this.coordinator,
  });

  final DeviceIdentity identity;
  final PairingService pairing;
  final SettingsManager settings;
  final PlayerCoordinator coordinator;

  static const int _port = 47890;
  static const Duration _stateBroadcastDebounce = Duration(milliseconds: 1000);

  final MdnsService _mdns = MdnsService();
  final Map<String, PeerDevice> _peers = {};
  final Map<String, LanSession> _sessions = {}; // peerId → session
  // accept 路径收到 hello 之前用 `host:port` 作临时 key
  final Map<String, LanSession> _pendingSessions = {};
  // 每个 peer 最近一次的远端状态快照（让 PlaylistMessage 复用 music/position/isPlaying）
  final Map<String, RemoteNowPlaying> _lastRemoteByPeer = {};

  ServerSocket? _server;
  StreamSubscription? _acceptSub;
  StreamSubscription? _mdnsPeerSub;
  StreamSubscription? _mdnsLostSub;

  final _peersController = StreamController<List<PeerDevice>>.broadcast();
  final _remoteNowPlayingController =
      StreamController<RemoteNowPlaying?>.broadcast();
  final _pinRequestsController = StreamController<PinRequest>.broadcast();
  final _pairingResultController = StreamController<PairingResult>.broadcast();

  bool _started = false;
  LanSyncMode _mode = LanSyncMode.off;
  Timer? _broadcastDebouncer;
  Timer? _playlistBroadcastDebouncer;
  final Map<String, String> _pendingPinCodes = {};

  /// 对端快照流（含连接状态、配对状态、last seen）。
  Stream<List<PeerDevice>> get peerList => _peersController.stream;

  /// 当前对端推送的"现在播放"。多个对端时取最新一次。
  Stream<RemoteNowPlaying?> get remoteNowPlaying =>
      _remoteNowPlayingController.stream;

  /// 服务端收到需要 PIN 的 hello 时触发（被动方）。
  Stream<PinRequest> get pinRequests => _pinRequestsController.stream;

  /// 主动方发起的配对结果（成功 / 失败 / 取消）。
  Stream<PairingResult> get pairingResults => _pairingResultController.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (PlatformHelper.isWeb) return;

    await identity.load();
    await pairing.load();
    await pairing.configureLocalId(identity.id);

    settings.addListener(_onSettingsChanged);

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      _acceptSub = _server!.listen(_onAccept);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LanSyncService: bind failed: $e');
      }
    }

    _mdnsPeerSub = _mdns.peerStream.listen(_onPeerDiscovered);
    _mdnsLostSub = _mdns.lostStream.listen(_onPeerLost);

    coordinator.currentIndexNotifier.addListener(_onCoordinatorChanged);
    coordinator.playerState.addListener(_onCoordinatorChanged);
    coordinator.playlist.addListener(_onPlaylistChanged);

    _onSettingsChanged();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    settings.removeListener(_onSettingsChanged);

    await _acceptSub?.cancel();
    _acceptSub = null;
    await _server?.close();
    _server = null;

    await _mdnsPeerSub?.cancel();
    await _mdnsLostSub?.cancel();
    await _mdns.stop();

    coordinator.currentIndexNotifier.removeListener(_onCoordinatorChanged);
    coordinator.playerState.removeListener(_onCoordinatorChanged);
    coordinator.playlist.removeListener(_onPlaylistChanged);

    _broadcastDebouncer?.cancel();
    _broadcastDebouncer = null;
    _playlistBroadcastDebouncer?.cancel();
    _playlistBroadcastDebouncer = null;

    for (final s in _sessions.values.toList()) {
      await s.dispose();
    }
    _sessions.clear();
    _pendingSessions.clear();
    _peers.clear();
    _lastRemoteByPeer.clear();
    if (!_peersController.isClosed) _peersController.add(const []);
  }

  void _onSettingsChanged() {
    final newMode = LanSyncMode.fromString(settings.lanSyncMode);
    if (newMode == _mode) return;
    _mode = newMode;
    unawaited(_mdns.start(identity: identity, mode: newMode, port: _port));
  }

  void _onAccept(Socket socket) {
    final session = LanSession.fromAcceptedSocket(socket);
    final key = '${socket.remoteAddress.address}:${socket.remotePort}';
    _pendingSessions[key] = session;
    session.messages.listen((msg) => _handleMessage(session, key, msg));
    session.stateChanges.listen((state) {
      _handleSessionState(session, key, state);
    });
    _sendHello(session);
  }

  void _onPeerDiscovered(PeerDevice peer) {
    if (peer.id == identity.id) return;
    final isPaired = pairing.expectedTokenFor(peer.id) != null;
    final updated = peer.copyWith(
      isPaired: isPaired,
      isConnected: _sessions.containsKey(peer.id),
      lastSeen: DateTime.now(),
    );
    _peers[peer.id] = updated;
    _emitPeers();
    if (_mode == LanSyncMode.private &&
        peer.mode == LanSyncMode.private &&
        isPaired &&
        !_sessions.containsKey(peer.id)) {
      unawaited(connectPaired(updated));
    }
  }

  void _onPeerLost(String peerId) {
    if (_peers.remove(peerId) != null) _emitPeers();
  }

  void _sendHello(LanSession session) {
    final token = pairing.selfToken.isNotEmpty ? pairing.selfToken : null;
    session.send(
      HelloMessage(
        id: identity.id,
        name: identity.name,
        platform: identity.platform,
        mode: _mode.mdnsValue,
        token: token,
      ),
    );
  }

  void _handleMessage(LanSession session, String keyOrPeerId, SyncMessage msg) {
    switch (msg) {
      case HelloMessage m:
        _handleHello(session, keyOrPeerId, m);
      case HelloAckMessage m:
        _handleHelloAck(session, keyOrPeerId, m);
      case PinMessage m:
        _handlePin(session, keyOrPeerId, m);
      case PinAckMessage m:
        _handlePinAck(session, keyOrPeerId, m);
      case StateMessage m:
        _handleState(session, m);
      case PlaylistMessage m:
        _handlePlaylist(session, m);
      case CmdMessage m:
        _handleCmd(session, m);
      case RosterMessage m:
        _handleRoster(session, m);
      case RevokeMessage m:
        _handleRevoke(session, m);
      case ByeMessage m:
        unawaited(_handleBye(session, m));
      case PingMessage _:
      case PongMessage _:
        // LanSession 已处理
        break;
    }
  }

  Future<void> _handleBye(LanSession session, ByeMessage m) async {
    if (m.reason == ByeReason.unpair &&
        session.peerId.isNotEmpty &&
        _sessions[session.peerId] == session) {
      await pairing.forgetPeer(session.peerId);
      final peer = _peers[session.peerId];
      if (peer != null) {
        _peers[session.peerId] = peer.copyWith(
          isPaired: false,
          isConnected: false,
        );
        _emitPeers();
      }
    }
    await session.close();
  }

  void _handleSessionState(
    LanSession session,
    String keyOrPeerId,
    LanSessionState state,
  ) {
    if (state == LanSessionState.closed) {
      _pendingSessions.remove(keyOrPeerId);
      if (session.peerId.isNotEmpty && _sessions[session.peerId] == session) {
        _sessions.remove(session.peerId);
        final peer = _peers[session.peerId];
        if (peer != null) {
          // isPaired intentionally NOT touched: token persists in PairingService
          // across disconnects; only the user-initiated `unpair` clears it.
          _peers[session.peerId] = peer.copyWith(isConnected: false);
          _emitPeers();
        }
      }
    } else if (state == LanSessionState.syncing) {
      if (session.peerId.isNotEmpty) {
        final peer = _peers[session.peerId];
        if (peer != null) {
          // Recompute isPaired: pairing.rememberPeerToken(...) at _handleHelloAck
          // / _handlePinAck may have just persisted a new token in-memory before
          // the session transitioned to syncing. Without this refresh, the
          // picker's `isPaired && isConnected` filter hides the device until
          // the next mDNS re-broadcast (up to minutes).
          final isPaired = pairing.expectedTokenFor(session.peerId) != null;
          _peers[session.peerId] = peer.copyWith(
            isConnected: true,
            isPaired: isPaired,
          );
          _emitPeers();
        }
      }
    }
  }

  void _handleHello(LanSession session, String key, HelloMessage msg) {
    if (session.peerId.isEmpty) {
      // accept 路径：补全身份
      session.setPeerIdentity(id: msg.id, name: msg.name);
      _pendingSessions.remove(key);
      final existing = _sessions[msg.id];
      if (existing != null && existing != session) {
        // 同时拨号时由较小 id 的设备保留主动连接，避免双方反复替换会话。
        final keepIncoming = identity.id.compareTo(msg.id) > 0;
        if (!keepIncoming) {
          unawaited(session.close());
          return;
        }
        unawaited(existing.close());
      }
      _sessions[msg.id] = session;
      // accept 路径里 B 可能尚未通过 mDNS 发现 A；按 hello 直接入 _peers，
      // 让 B 端 UI 立刻可见。后续 _onPeerDiscovered 到达会用 copyWith 覆盖，
      // _handleSessionState(syncing) 会再把 isConnected 翻成 true。
      if (!_peers.containsKey(msg.id)) {
        _peers[msg.id] = PeerDevice(
          id: msg.id,
          name: msg.name,
          platform: msg.platform,
          mode: LanSyncMode.fromString(msg.mode),
          host: session.host,
          port: session.port,
          lastSeen: DateTime.now(),
          isPaired: pairing.expectedTokenFor(msg.id) != null,
          isConnected: false,
        );
      }
    } else if (session.peerId != msg.id) {
      if (kDebugMode) {
        debugPrint('LanSyncService: hello id mismatch');
      }
      unawaited(session.close());
      return;
    }

    session.peerProtocolVersion = msg.version;
    final peerMode = LanSyncMode.fromString(msg.mode);
    final privateCandidate =
        _mode == LanSyncMode.private && peerMode == LanSyncMode.private;
    final knownToken = pairing.expectedTokenFor(msg.id);
    final tokenMatches =
        knownToken != null && msg.token != null && msg.token == knownToken;

    if (privateCandidate && tokenMatches) {
      session.isPrivate = true;
      session.send(
        HelloAckMessage(
          ok: true,
          peerId: identity.id,
          peerName: identity.name,
          token: pairing.selfToken.isNotEmpty ? pairing.selfToken : null,
          version: 2,
        ),
      );
      session.transitionTo(LanSessionState.syncing);
      _sendCurrentState(session);
      _sendRoster(session);
    } else if (privateCandidate) {
      session.send(
        const HelloAckMessage(ok: false, reason: 'need_pin', version: 2),
      );
      // 仅被动方需要本地弹 PIN 框：发起方已在 pairWith 时预填了 PIN，
      // 待收到对方的 hello-ack{need_pin} 时由 _handleHelloAck 自动发送。
      if (!session.isInitiator) {
        _pinRequestsController.add(
          PinRequest(peerId: msg.id, peerName: msg.name),
        );
      }
      // 等待 PIN；state 留在 helloSent
    } else {
      // 公共模式：直接接受只读；不传播私有拓扑。
      session.send(
        HelloAckMessage(
          ok: true,
          peerId: identity.id,
          peerName: identity.name,
          token: pairing.selfToken.isNotEmpty ? pairing.selfToken : null,
          version: 2,
        ),
      );
      session.transitionTo(LanSessionState.syncing);
      _sendCurrentState(session);
    }
  }

  void _handleHelloAck(LanSession session, String peerId, HelloAckMessage msg) {
    session.peerProtocolVersion = msg.version;
    if (msg.ok) {
      final knownToken = pairing.expectedTokenFor(peerId);
      final tokenMatches =
          knownToken != null && msg.token != null && msg.token == knownToken;
      if (session.expectsPrivate && !tokenMatches) {
        unawaited(session.close());
        return;
      }
      if (!session.isPrivate) {
        session.isPrivate = session.expectsPrivate && tokenMatches;
      }
      session.transitionTo(LanSessionState.syncing);
      _sendCurrentState(session);
      if (session.isPrivate) _sendRoster(session);
    } else if (msg.reason == 'need_pin') {
      session.transitionTo(LanSessionState.awaitingPin);
      // 用户先前在 pairWith 里预填过 PIN：直接发
      final pending = _pendingPinCodes.remove(peerId);
      if (pending != null) {
        session.send(PinMessage(code: pending, token: pairing.selfToken));
      } else if (session.isInitiator) {
        // 兜底：发起方走到这里意味着 pairWith 未预填 PIN（当前 UI 不会
        // 触发，留作将来"无 PIN 主动连接"入口的兼容路径）。
        _pinRequestsController.add(
          PinRequest(peerId: peerId, peerName: session.peerName),
        );
      }
    } else {
      unawaited(session.close());
    }
  }

  void _handlePin(LanSession session, String key, PinMessage msg) {
    if (!pairing.verifyPin(msg.code)) {
      session.send(const PinAckMessage(ok: false));
      unawaited(session.close());
      return;
    }
    // 主动方在本端只会走 pairWith 的预填 PIN 路径 _handleHelloAck，
    // 不会到达这里。落到这里的都是被动方（B 端）：
    // B 自己的 PIN 校验通过后还不能立即握手，还要等用户在
    // PairRequestDialog 里输入"A 的 PIN"由 [acceptPeerPairing] 回传。
    if (session.state != LanSessionState.awaitingPin) {
      session.transitionTo(LanSessionState.awaitingPin);
    }
    if (!session.isInitiator) {
      _pinRequestsController.add(
        PinRequest(peerId: session.peerId, peerName: session.peerName),
      );
    }
  }

  void _handlePinAck(LanSession session, String peerId, PinAckMessage msg) {
    if (!msg.ok) {
      _pairingResultController.add(
        PairingResult(peerId: peerId, ok: false, reason: '对端拒绝或 PIN 错误'),
      );
      unawaited(session.close());
      return;
    }
    if (session.isInitiator) {
      // A 端：B 用户在 PairRequestDialog 输入的"A 的 PIN"在 msg.code 里。
      // A 用本端 verifyPin 校验它是否等于 A 自己的 PIN。
      if (msg.code == null || !pairing.verifyPin(msg.code!)) {
        session.send(const PinAckMessage(ok: false));
        _pairingResultController.add(
          PairingResult(peerId: peerId, ok: false, reason: '对端 PIN 错误'),
        );
        unawaited(session.close());
        return;
      }
      // 双方 PIN 都验证通过
      if (msg.token != null && msg.token!.isNotEmpty) {
        unawaited(pairing.rememberDirectPeer(peerId, msg.token!));
      }
      session.send(
        PinAckMessage(
          ok: true,
          token: pairing.selfToken.isNotEmpty ? pairing.selfToken : null,
        ),
      );
      session.isPrivate = true;
      session.transitionTo(LanSessionState.syncing);
      _sendCurrentState(session);
      _sendRoster(session);
      _pairingResultController.add(PairingResult(peerId: peerId, ok: true));
    } else {
      // B 端：A 发回的最终回执——双方 PIN 都已通过验证，进入 syncing。
      if (msg.token != null && msg.token!.isNotEmpty) {
        unawaited(pairing.rememberDirectPeer(peerId, msg.token!));
      }
      session.isPrivate = true;
      session.transitionTo(LanSessionState.syncing);
      _sendCurrentState(session);
      _sendRoster(session);
    }
  }

  // TODO(未实现功能): 远端「现在播放」接收链（→ remoteNowPlayingController →
  // remoteNowPlayingProvider）目前无 UI 消费，属未完成的新功能，暂保留；
  // 实现「查看对端播放」UI 后接入，届时仍未用可整链删除。
  void _handleState(LanSession session, StateMessage msg) {
    final remote = RemoteNowPlaying(
      peerId: session.peerId,
      peerName: session.peerName,
      music: msg.music,
      position: Duration(milliseconds: msg.positionMs),
      isPlaying: msg.isPlaying,
      queue: msg.queue,
      currentIndex: msg.currentIndex,
    );
    _lastRemoteByPeer[session.peerId] = remote;
    if (!_remoteNowPlayingController.isClosed) {
      _remoteNowPlayingController.add(remote);
    }
  }

  void _handlePlaylist(LanSession session, PlaylistMessage msg) {
    if (!session.isPrivate) return;
    final last = _lastRemoteByPeer[session.peerId];
    final remote = RemoteNowPlaying(
      peerId: session.peerId,
      peerName: session.peerName,
      music: last?.music,
      position: last?.position ?? Duration.zero,
      isPlaying: last?.isPlaying ?? false,
      queue: msg.queue,
      currentIndex: msg.currentIndex,
    );
    _lastRemoteByPeer[session.peerId] = remote;
    if (!_remoteNowPlayingController.isClosed) {
      _remoteNowPlayingController.add(remote);
    }
  }

  void _handleRoster(LanSession session, RosterMessage message) {
    if (!session.isPrivate) return;
    unawaited(_mergeRosterAndConnect(message.edges));
  }

  Future<void> _mergeRosterAndConnect(List<Map<String, String>> edges) async {
    final changed = await pairing.mergeRoster(edges);
    if (!changed) return;
    _refreshPeerPairingStates();
    for (final session in _sessions.values) {
      if (session.state == LanSessionState.syncing && session.isPrivate) {
        _sendRoster(session);
      }
    }
    _connectKnownPrivatePeers();
  }

  Future<void> _handleRevoke(LanSession session, RevokeMessage message) async {
    if (!session.isPrivate) return;
    await pairing.removeEdge(message.a, message.b);
    _refreshPeerPairingStates();
    final revoked = <String>[];
    for (final entry in _sessions.entries.toList()) {
      if (entry.key == identity.id) continue;
      if (pairing.expectedTokenFor(entry.key) == null) {
        revoked.add(entry.key);
        await entry.value.close(reason: ByeReason.unpair);
      }
    }
    for (final peerId in revoked) {
      _sessions.remove(peerId);
    }
    _emitPeers();
  }

  void _sendRoster(LanSession session) {
    if (!session.isPrivate ||
        session.peerProtocolVersion < 2 ||
        session.state != LanSessionState.syncing) {
      return;
    }
    session.send(RosterMessage(edges: pairing.rosterEdges));
  }

  void _refreshPeerPairingStates() {
    for (final entry in _peers.entries.toList()) {
      final isPaired = pairing.expectedTokenFor(entry.key) != null;
      _peers[entry.key] = entry.value.copyWith(isPaired: isPaired);
    }
    _emitPeers();
  }

  void _connectKnownPrivatePeers() {
    if (_mode != LanSyncMode.private) return;
    for (final peer in _peers.values) {
      if (peer.mode != LanSyncMode.private ||
          pairing.expectedTokenFor(peer.id) == null ||
          _sessions.containsKey(peer.id)) {
        continue;
      }
      unawaited(connectPaired(peer));
    }
  }

  void _handleCmd(LanSession session, CmdMessage msg) {
    if (!session.isPrivate) return; // 公共模式不接受 cmd
    switch (msg.action) {
      case 'pause':
        unawaited(coordinator.pause());
      case 'play':
      case 'resume':
        unawaited(coordinator.resume());
      case 'seek':
        final ms = msg.payload?['positionMs'];
        if (ms is int) unawaited(coordinator.seek(Duration(milliseconds: ms)));
      case 'next':
        unawaited(coordinator.playNext());
      case 'prev':
        unawaited(coordinator.playPrevious());
      case 'playAt':
        final idx = msg.payload?['index'];
        if (idx is int) unawaited(coordinator.playAtIndex(idx));
      case 'playMusic':
        final m = msg.payload?['music'];
        if (m is Map<String, dynamic>) {
          try {
            final music = Music.fromJson(m);
            unawaited(coordinator.playMusic(music));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('LanSyncService: playMusic failed: $e');
            }
          }
        }
    }
  }

  void _onCoordinatorChanged() {
    if (_mode == LanSyncMode.off) return;
    _broadcastDebouncer?.cancel();
    _broadcastDebouncer = Timer(
      _stateBroadcastDebounce,
      _broadcastStateToSyncingSessions,
    );
  }

  void _onPlaylistChanged() {
    if (!_mode.acceptsPrivate) return;
    _playlistBroadcastDebouncer?.cancel();
    _playlistBroadcastDebouncer = Timer(
      _stateBroadcastDebounce,
      _broadcastPlaylistToSyncingSessions,
    );
  }

  void _broadcastStateToSyncingSessions() {
    final music = coordinator.currentMusic;
    final msg = StateMessage(
      music: music,
      positionMs: coordinator.position.value.inMilliseconds,
      isPlaying: coordinator.isPlaying,
    );
    for (final session in _sessions.values) {
      if (session.state == LanSessionState.syncing) {
        session.send(msg);
      }
    }
  }

  void _broadcastPlaylistToSyncingSessions() {
    final msg = PlaylistMessage(
      queue: coordinator.playlist.value,
      currentIndex: coordinator.currentIndex ?? 0,
    );
    for (final session in _sessions.values) {
      if (session.state == LanSessionState.syncing && session.isPrivate) {
        session.send(msg);
      }
    }
  }

  void _sendCurrentState(LanSession session) {
    if (session.state != LanSessionState.syncing) return;
    final music = coordinator.currentMusic;
    final msg = StateMessage(
      music: music,
      positionMs: coordinator.position.value.inMilliseconds,
      isPlaying: coordinator.isPlaying,
    );
    session.send(msg);
    if (session.isPrivate) {
      session.send(
        PlaylistMessage(
          queue: coordinator.playlist.value,
          currentIndex: coordinator.currentIndex ?? 0,
        ),
      );
    }
  }

  void _emitPeers() {
    final list = _peers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!_peersController.isClosed) _peersController.add(list);
  }

  // ==================== UI 入口 ====================

  /// 把 [music] 推送到 [peerId] 对应的私有会话对端播放。
  ///
  /// 仅当该 peer 已完成私有 + token 握手且 session 处于 `syncing` 时才发；
  /// 否则静默丢弃（调用方根据 toast 文案自处理）。
  void pushMusicToPeer(String peerId, Music music) {
    final session = _sessions[peerId];
    if (session == null) return;
    if (session.state != LanSessionState.syncing) return;
    if (!session.isPrivate) return;
    session.send(
      CmdMessage(action: 'playMusic', payload: {'music': music.toJson()}),
    );
  }

  /// 主动发起配对：用户已在 UI 输入对端 PIN。
  ///
  /// 流程：TCP connect → 发送 hello → 收到 hello-ack { need_pin } → 发送 pin。
  Future<void> pairWith(PeerDevice peer, String pinCode) =>
      _startPair(peer, pinCode: pinCode);

  /// 主动发起公共只读连接：不预填 PIN，由对端 _handleHello 判定公共模式后
  /// 直接发 hello-ack{ok=true} 完成握手。
  Future<void> connectPublic(PeerDevice peer) => _startPair(peer);

  /// 用已存 token 主动连接已配对对端（免 PIN）。
  ///
  /// 流程与 [pairWith] 类似，但 hello 自带 token —— 对端 [_handleHello]
  /// 在 token 匹配时直接 hello-ack{ok=true}，跳过 PIN 等待。
  /// token 缺失时降级走 [pairWith]（UI 会弹 PIN）；token 失效时由对端
  /// _handleHelloAck 返回 need_pin，再走 PIN 流。
  Future<void> connectPaired(PeerDevice peer) async {
    final token = pairing.expectedTokenFor(peer.id);
    if (token == null) {
      // token 缺失视为"需要走 PIN"，调用方 UI 应弹 PIN 框
      return pairWith(peer, '');
    }
    if (_sessions.containsKey(peer.id)) return;

    final session = LanSession.fromPeer(peer, expectsPrivate: true);
    _sessions[peer.id] = session;
    session.messages.listen((msg) => _handleMessage(session, peer.id, msg));
    session.stateChanges.listen((state) {
      _handleSessionState(session, peer.id, state);
    });
    await session.connect();
    if (session.state == LanSessionState.closed) {
      _sessions.remove(peer.id);
      return;
    }
    session.transitionTo(LanSessionState.helloSent);
    // 关键：hello 携带本机 selfToken，让对端 _handleHello 直接放行
    _sendHello(session);
  }

  Future<void> _startPair(PeerDevice peer, {String? pinCode}) async {
    // 已有 awaitingPin 的 session：直接发 pin
    final existing = _sessions[peer.id];
    if (existing != null) {
      if (existing.state == LanSessionState.awaitingPin && pinCode != null) {
        existing.send(PinMessage(code: pinCode, token: pairing.selfToken));
      }
      return;
    }

    final session = LanSession.fromPeer(peer, expectsPrivate: pinCode != null);
    _sessions[peer.id] = session;
    session.messages.listen((msg) => _handleMessage(session, peer.id, msg));
    session.stateChanges.listen((state) {
      _handleSessionState(session, peer.id, state);
    });
    await session.connect();
    if (session.state == LanSessionState.closed) {
      _sessions.remove(peer.id);
      return;
    }
    session.transitionTo(LanSessionState.helloSent);
    _sendHello(session);
    // 等待 hello-ack 决定后续动作；如果 ack 需要 PIN，UI 通过 pinRequests 流收到通知
    // 这里预先把 PIN 存起来，等 ack 到达时由 hello-ack 处理器使用
    if (pinCode != null) _pendingPinCodes[peer.id] = pinCode;
  }

  /// 被动方（B）接受配对：用户在 PairRequestDialog 输入了对端（A）的 PIN。
  ///
  /// 把 PIN 通过 PinAck.code 回传给 A，由 A 端做最终 verifyPin 校验。
  Future<void> acceptPeerPairing(String peerId, String peerPin) async {
    final session = _sessions[peerId];
    if (session == null) return;
    if (session.state != LanSessionState.awaitingPin) return;
    session.send(
      PinAckMessage(
        ok: true,
        code: peerPin,
        token: pairing.selfToken.isNotEmpty ? pairing.selfToken : null,
      ),
    );
  }

  /// 被动方（B）拒绝配对：通知 A 端并关闭会话。
  Future<void> rejectPeerPairing(String peerId) async {
    final session = _sessions[peerId];
    if (session == null) return;
    session.send(const PinAckMessage(ok: false));
    unawaited(session.close());
  }

  /// 主动方（A）取消正在进行的配对：关闭会话并清理 pending 状态。
  Future<void> cancelInitiatedPairing(String peerId) async {
    final session = _sessions.remove(peerId);
    _pendingPinCodes.remove(peerId);
    if (session != null) {
      session.send(const ByeMessage());
      unawaited(session.close());
    }
    _pairingResultController.add(
      PairingResult(peerId: peerId, ok: false, reason: '已取消'),
    );
  }

  /// 关闭与对端的 TCP 会话但保留 token，允许后续免 PIN 重连。
  ///
  /// 与 [unpair] 的区别：不调用 [PairingService.forgetPeer]，
  /// 因此对端 [PeerDevice.isPaired] 仍为 true，可在卡片上点"连接"重连。
  /// 发送 [ByeReason.disconnect] 让对端同步关闭 session。
  Future<void> disconnect(String peerId) async {
    final session = _sessions.remove(peerId);
    _pendingPinCodes.remove(peerId);
    await session?.close(reason: ByeReason.disconnect);
    final peer = _peers[peerId];
    if (peer != null) {
      _peers[peerId] = peer.copyWith(isConnected: false);
      _emitPeers();
    }
  }

  /// 取消对某个对端的配对（关闭 session + 删除直接配对边）。
  Future<void> unpair(String peerId) async {
    final session = _sessions.remove(peerId);
    _pendingPinCodes.remove(peerId);
    final revoke = RevokeMessage(a: identity.id, b: peerId);
    for (final peerSession in _sessions.values) {
      if (peerSession.state == LanSessionState.syncing &&
          peerSession.isPrivate &&
          peerSession.peerProtocolVersion >= 2) {
        peerSession.send(revoke);
      }
    }
    await pairing.forgetPeer(peerId);
    await session?.close(reason: ByeReason.unpair);
    final peer = _peers[peerId];
    if (peer != null) {
      _peers[peerId] = peer.copyWith(isPaired: false, isConnected: false);
      _emitPeers();
    }
    _refreshPeerPairingStates();
  }

  /// 关闭后释放所有资源（关闭 controllers）。
  Future<void> dispose() async {
    await stop();
    if (!_peersController.isClosed) await _peersController.close();
    if (!_remoteNowPlayingController.isClosed) {
      await _remoteNowPlayingController.close();
    }
    if (!_pinRequestsController.isClosed) await _pinRequestsController.close();
    if (!_pairingResultController.isClosed) {
      await _pairingResultController.close();
    }
  }
}
