import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:bilimusic/models/sync/peer_device.dart';
import 'package:bilimusic/models/sync/sync_message.dart';
import 'package:bilimusic/services/sync/sync_protocol.dart';

/// 单 peer TCP 会话状态。
enum LanSessionState {
  /// 正在 TCP connect。
  connecting,

  /// TCP 已建立，hello 已发出，等待对方的 hello-ack。
  helloSent,

  /// 等待对方输入 PIN（对方 hello-ack 报告需要 PIN）。
  awaitingPin,

  /// 已完成握手，可双向收发业务消息。
  syncing,

  /// 主动关闭中。
  closing,

  /// 已关闭（无法再发送）。
  closed,
}

/// 单个对端的 TCP 会话。
///
/// 负责 socket 连接、帧编解码、心跳。把所有收到的 [SyncMessage] 推到
/// [messages] 流；协议层面的 hello/pin 握手由上层服务处理。
class LanSession {
  /// 本端是否主动发起 TCP 连接（`true`）还是被动接受（`false`）。
  ///
  /// 用于协议层区分"发起方"与"被动方"——例如发起方的会话在收到对方 hello
  /// 时不应再触发 PIN 输入弹窗（PIN 已在 [LanSyncService.pairWith] 预填）。
  final bool isInitiator;

  /// 本端发起连接时使用对端的 host:port。
  final InternetAddress host;

  /// 端口。
  final int port;

  /// 对端 id；在收到对方 hello 之前可能是 `''`（accept 路径）。
  String peerId;

  /// 对端显示名。
  String peerName;

  /// 对端支持的 LAN Sync 协议版本；旧客户端未携带版本时按 v1 处理。
  int peerProtocolVersion = 1;

  /// 当前会话是否按 private 方式发起，避免 public ack 携带 token 时被误升权。
  bool expectsPrivate = false;

  /// 当前会话是否经私有 + token 校验建立。
  ///
  /// 由 [LanSyncService] 在私有握手分支置 `true`；公共只读会话保持 `false`。
  /// UI 用此判断是否能向对端发起需要写权限的指令（如 push 音乐）。
  bool isPrivate = false;

  Socket? _socket;
  LanSessionState _state = LanSessionState.connecting;
  Uint8List _recvBuffer = Uint8List(0);

  final _messages = StreamController<SyncMessage>.broadcast();
  final _stateChanges = StreamController<LanSessionState>.broadcast();
  Timer? _pingTimer;
  Timer? _pongWatchdog;

  /// 当前状态。
  LanSessionState get state => _state;

  /// 收到的协议消息流（不含 ping/pong——心跳由本类内部处理）。
  Stream<SyncMessage> get messages => _messages.stream;

  /// 状态变化流。
  Stream<LanSessionState> get stateChanges => _stateChanges.stream;

  LanSession._({
    required this.isInitiator,
    required this.host,
    required this.port,
    this.peerId = '',
    this.peerName = '',
    Socket? socket,
  }) : _socket = socket {
    if (socket != null) _attach();
  }

  /// 构造一个尚未连接的会话（用于 [connect] 路径）。发起方。
  factory LanSession.fromPeer(PeerDevice peer, {bool expectsPrivate = false}) {
    final session = LanSession._(
      isInitiator: true,
      host: peer.host,
      port: peer.port,
      peerId: peer.id,
      peerName: peer.name,
    );
    session.expectsPrivate = expectsPrivate;
    return session;
  }

  /// 构造一个表示"已接受 TCP 连接"的会话（用于 ServerSocket 路径）。被动方。
  ///
  /// 接收首个 hello 后再用 [setPeerIdentity] 填入真实 id/name。
  factory LanSession.fromAcceptedSocket(Socket socket) {
    return LanSession._(
      isInitiator: false,
      host: socket.remoteAddress,
      port: socket.remotePort,
      socket: socket,
    );
  }

  /// 主动连接到对端。连接失败时进入 [LanSessionState.closed]。
  Future<void> connect() async {
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      _attach();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LanSession.connect failed: $e');
      }
      _setState(LanSessionState.closed);
    }
  }

  void _attach() {
    final s = _socket!;
    s.listen(_onData, onError: _onError, onDone: _onDone, cancelOnError: false);
  }

  void _onData(Uint8List data) {
    if (data.isEmpty) return;
    final combined = Uint8List(_recvBuffer.length + data.length);
    combined.setRange(0, _recvBuffer.length, _recvBuffer);
    combined.setRange(_recvBuffer.length, combined.length, data);
    _recvBuffer = combined;

    while (true) {
      final (msg, consumed) = SyncProtocol.tryDecode(_recvBuffer);
      if (msg == null) break;
      _recvBuffer = _recvBuffer.sublist(consumed);
      if (msg is PingMessage) {
        send(const PongMessage());
        continue;
      }
      if (msg is PongMessage) {
        _onPong();
        continue;
      }
      if (!_messages.isClosed) _messages.add(msg);
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (kDebugMode) {
      debugPrint('LanSession socket error: $error');
    }
    // Socket errors are terminal for this session. Close it immediately so
    // the heartbeat does not continue writing to a reset connection.
    unawaited(close());
  }

  void _onDone() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    _socket = null;
    _setState(LanSessionState.closed);
  }

  /// 发送一条消息。已关闭或无 socket 时静默丢弃。
  void send(SyncMessage message) {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(SyncProtocol.encode(message));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LanSession.send failed: $e');
      }
    }
  }

  /// 状态机外部推进：协商完成 / 进入 PIN 等待 / 进入 syncing。
  void transitionTo(LanSessionState newState) {
    _setState(newState);
    if (newState == LanSessionState.syncing) {
      _startHeartbeat();
    }
  }

  /// 在收到对方 hello 后回填对端身份。
  void setPeerIdentity({required String id, required String name}) {
    peerId = id;
    peerName = name;
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pongWatchdog?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_state == LanSessionState.syncing) {
        send(const PingMessage());
        _pongWatchdog?.cancel();
        _pongWatchdog = Timer(const Duration(seconds: 5), () {
          if (kDebugMode) {
            debugPrint('LanSession: pong timeout, closing');
          }
          close();
        });
      }
    });
  }

  void _onPong() {
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
  }

  void _setState(LanSessionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateChanges.isClosed) _stateChanges.add(newState);
  }

  /// 优雅关闭：发 bye → flush → close socket。
  Future<void> close({ByeReason reason = ByeReason.disconnect}) async {
    if (_state == LanSessionState.closed) return;
    _setState(LanSessionState.closing);
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    final s = _socket;
    if (s != null) {
      try {
        send(ByeMessage(reason: reason));
        await s.flush();
        await s.close();
      } catch (_) {}
    }
    _socket = null;
    _setState(LanSessionState.closed);
  }

  /// 完全释放（关闭流 + 关闭 socket）。调用后本对象不可再使用。
  Future<void> dispose() async {
    await close();
    if (!_messages.isClosed) await _messages.close();
    if (!_stateChanges.isClosed) await _stateChanges.close();
  }
}
