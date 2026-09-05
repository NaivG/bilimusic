import 'package:bilimusic/models/music.dart';

/// LAN 同步协议消息密封类。
///
/// 所有变体通过 `SyncProtocol.encode` 序列化为 `4 字节大端长度 + UTF-8 JSON`。
sealed class SyncMessage {
  const SyncMessage();

  /// 序列化为 JSON Map。`'t'` 字段是消息类型标识。
  Map<String, dynamic> toJson();
}

/// 客户端握手：声明身份 + 模式 + 本端 token。
///
/// 首次连接 `token = null`；已配对过的连接 `token = 配对时生成的 hex 字符串`。
final class HelloMessage extends SyncMessage {
  final String id;
  final String name;
  final String platform;
  final String mode; // 'private' | 'public'
  final String? token;
  final int version;

  const HelloMessage({
    required this.id,
    required this.name,
    required this.platform,
    required this.mode,
    this.token,
    this.version = 2,
  });

  @override
  Map<String, dynamic> toJson() => {
    't': 'hello',
    'id': id,
    'name': name,
    'platform': platform,
    'mode': mode,
    'ver': version,
    if (token != null) 'token': token,
  };
}

/// 服务端对 hello 的回应。
///
/// `ok = true` → 直接进入 syncing；`ok = false` 且 `reason = 'need_pin'` → 对端需发送 `PinMessage`。
/// `token` 字段在 `ok = true` 时携带本端 token，对端用它做未来的 hello 验证。
final class HelloAckMessage extends SyncMessage {
  final bool ok;
  final String? reason;
  final String? peerId;
  final String? peerName;
  final String? token;
  final int version;

  const HelloAckMessage({
    required this.ok,
    this.reason,
    this.peerId,
    this.peerName,
    this.token,
    this.version = 1,
  });

  @override
  Map<String, dynamic> toJson() => {
    't': 'hello-ack',
    'ok': ok,
    if (reason != null) 'reason': reason,
    if (peerId != null) 'id': peerId,
    if (peerName != null) 'name': peerName,
    'ver': version,
    if (token != null) 'token': token,
  };
}

/// 私有模式配对：发起方提交对端的 6 位 PIN，并携带本端 token（首次连接时生成）。
final class PinMessage extends SyncMessage {
  final String code;
  final String? token;

  const PinMessage({required this.code, this.token});

  @override
  Map<String, dynamic> toJson() => {
    't': 'pin',
    'code': code,
    if (token != null) 'token': token,
  };
}

/// 配对结果。
///
/// - `ok = false`：对端拒绝 / PIN 错误。
/// - `ok = true` 时：
///   - `code` 携带被动方（B）用户输入的"对端（A）的 PIN"，由 A 端 verifyPin 校验。
///   - `token` 携带发送方的 selfToken，对端用它做未来的 hello 验证。
///   - A 端校验通过后会再发一次 `PinAckMessage(ok=true, token=A.selfToken)`（无 code）
///     作为最终回执，B 端收到后才进入 syncing——双方 PIN 都通过才会成功握手。
final class PinAckMessage extends SyncMessage {
  final bool ok;
  final String? code;
  final String? token;

  const PinAckMessage({required this.ok, this.code, this.token});

  @override
  Map<String, dynamic> toJson() => {
    't': 'pin-ack',
    'ok': ok,
    if (code != null) 'code': code,
    if (token != null) 'token': token,
  };
}

/// 现在播放状态广播。
///
/// 私有模式：携带 `music + position + isPlaying + queue + currentIndex`。
/// 公共模式：仅携带 `music + position + isPlaying`（`queue` 字段被省略）。
final class StateMessage extends SyncMessage {
  final Music? music;
  final int positionMs;
  final bool isPlaying;
  final List<Music> queue;
  final int currentIndex;

  const StateMessage({
    this.music,
    this.positionMs = 0,
    this.isPlaying = false,
    this.queue = const [],
    this.currentIndex = 0,
  });

  @override
  Map<String, dynamic> toJson() {
    final m = {
      't': 'state',
      'music': music?.toJson(),
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'currentIndex': currentIndex,
    };
    if (queue.isNotEmpty) {
      m['queue'] = queue.map((e) => e.toJson()).toList();
    }
    return m;
  }
}

/// 正在播放歌单变更广播（仅私有模式）。
///
/// 与 [StateMessage] 解耦：本消息仅在 `coordinator.playlist` 变化时触发，
/// 携带完整的 `queue + currentIndex`，用于对端镜像本端的"现在播放列表"。
/// 播放状态（曲目 / 进度 / 暂停）由独立的 [StateMessage] 同步。
final class PlaylistMessage extends SyncMessage {
  final List<Music> queue;
  final int currentIndex;

  const PlaylistMessage({this.queue = const [], this.currentIndex = 0});

  @override
  Map<String, dynamic> toJson() => {
    't': 'playlist',
    'currentIndex': currentIndex,
    if (queue.isNotEmpty) 'queue': queue.map((e) => e.toJson()).toList(),
  };
}

/// 远程控制指令（仅私有模式接收）。
///
/// `action` ∈ `play` | `pause` | `resume` | `seek` | `next` | `prev` | `playAt`。
final class CmdMessage extends SyncMessage {
  final String action;
  final Map<String, dynamic>? payload;

  const CmdMessage({required this.action, this.payload});

  @override
  Map<String, dynamic> toJson() => {
    't': 'cmd',
    'action': action,
    if (payload != null) 'payload': payload,
  };
}

/// 私有群组拓扑快照。
///
/// 每条边表示一次已验证的直接私有配对。该消息只允许在 private 会话中传播；
/// mDNS 发现本身不会触发群组加入。
final class RosterMessage extends SyncMessage {
  final List<Map<String, String>> edges;

  const RosterMessage({this.edges = const []});

  @override
  Map<String, dynamic> toJson() => {'t': 'roster', 'edges': edges};
}

/// 私有配对边撤销通知。
final class RevokeMessage extends SyncMessage {
  final String a;
  final String b;

  const RevokeMessage({required this.a, required this.b});

  @override
  Map<String, dynamic> toJson() => {'t': 'revoke', 'a': a, 'b': b};
}

/// 心跳。
final class PingMessage extends SyncMessage {
  const PingMessage();
  @override
  Map<String, dynamic> toJson() => {'t': 'ping'};
}

/// 心跳应答。
final class PongMessage extends SyncMessage {
  const PongMessage();
  @override
  Map<String, dynamic> toJson() => {'t': 'pong'};
}

/// 主动断开通知的语义。
enum ByeReason {
  /// 普通断开（心跳超时、用户关闭 LAN 同步等）。
  disconnect,

  /// 主动取消私有配对。接收方应同步清除本地持有的对端 token。
  unpair,
}

/// 主动断开通知。
final class ByeMessage extends SyncMessage {
  const ByeMessage({this.reason = ByeReason.disconnect});
  final ByeReason reason;
  @override
  Map<String, dynamic> toJson() => {'t': 'bye', 'reason': reason.name};
}
