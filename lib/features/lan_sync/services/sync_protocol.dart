import 'dart:convert';
import 'dart:typed_data';

import 'package:bilimusic/models/sync/sync_message.dart';
import 'package:bilimusic/models/music.dart';

/// LAN 同步协议帧编解码。
///
/// 帧格式：4 字节大端无符号长度头 + UTF-8 JSON 负载。
/// 单帧上限 4 MB；超过即视为协议错误。
class SyncProtocol {
  /// 单帧负载最大字节数。超过会抛 [StateError]。
  static const int maxFrameBytes = 4 * 1024 * 1024;

  /// 长度头字节数。
  static const int headerBytes = 4;

  /// 把 [message] 编码为完整帧。
  static Uint8List encode(SyncMessage message) {
    final json = jsonEncode(message.toJson());
    final payload = utf8.encode(json);
    if (payload.length > maxFrameBytes) {
      throw StateError('frame payload too large: ${payload.length} bytes');
    }
    final header = ByteData(headerBytes)
      ..setUint32(0, payload.length, Endian.big);
    final result = Uint8List(headerBytes + payload.length);
    result.setRange(0, headerBytes, header.buffer.asUint8List());
    result.setRange(headerBytes, headerBytes + payload.length, payload);
    return result;
  }

  /// 从累积的 [buffer] 尝试解析一帧。
  ///
  /// 返回 `(message, consumedBytes)`：
  /// - 成功解析 → `(message, 4 + payloadLen)`
  /// - 缓冲区不足一帧 → `(null, 0)`，调用方继续累积
  /// - 帧长度超限 → 抛 [StateError]
  static (SyncMessage?, int) tryDecode(Uint8List buffer) {
    if (buffer.length < headerBytes) return (null, 0);
    final length = ByteData.sublistView(
      buffer,
      0,
      headerBytes,
    ).getUint32(0, Endian.big);
    if (length > maxFrameBytes) {
      throw StateError('frame payload too large: $length bytes');
    }
    if (buffer.length < headerBytes + length) return (null, 0);
    final json = utf8.decode(buffer.sublist(headerBytes, headerBytes + length));
    final map = jsonDecode(json) as Map<String, dynamic>;
    return (_fromJson(map), headerBytes + length);
  }

  static SyncMessage _fromJson(Map<String, dynamic> json) {
    final type = json['t'];
    if (type is! String) {
      throw StateError('missing message type');
    }
    switch (type) {
      case 'hello':
        return HelloMessage(
          id: json['id'] as String,
          name: json['name'] as String,
          platform: json['platform'] as String,
          mode: json['mode'] as String,
          token: json['token'] as String?,
          version: json['ver'] as int? ?? 1,
        );
      case 'hello-ack':
        return HelloAckMessage(
          ok: json['ok'] as bool,
          reason: json['reason'] as String?,
          peerId: json['id'] as String?,
          peerName: json['name'] as String?,
          token: json['token'] as String?,
          version: json['ver'] as int? ?? 1,
        );
      case 'pin':
        return PinMessage(
          code: json['code'] as String,
          token: json['token'] as String?,
        );
      case 'pin-ack':
        return PinAckMessage(
          ok: json['ok'] as bool,
          code: json['code'] as String?,
          token: json['token'] as String?,
        );
      case 'state':
        return StateMessage(
          music: json['music'] == null
              ? null
              : Music.fromJson(Map<String, dynamic>.from(json['music'] as Map)),
          positionMs: json['positionMs'] as int? ?? 0,
          isPlaying: json['isPlaying'] as bool? ?? false,
          queue:
              (json['queue'] as List?)
                  ?.map(
                    (e) => Music.fromJson(Map<String, dynamic>.from(e as Map)),
                  )
                  .toList() ??
              const [],
          currentIndex: json['currentIndex'] as int? ?? 0,
        );
      case 'playlist':
        return PlaylistMessage(
          queue:
              (json['queue'] as List?)
                  ?.map(
                    (e) => Music.fromJson(Map<String, dynamic>.from(e as Map)),
                  )
                  .toList() ??
              const [],
          currentIndex: json['currentIndex'] as int? ?? 0,
        );
      case 'cmd':
        return CmdMessage(
          action: json['action'] as String,
          payload: json['payload'] == null
              ? null
              : Map<String, dynamic>.from(json['payload'] as Map),
        );
      case 'roster':
        return RosterMessage(
          edges:
              (json['edges'] as List?)
                  ?.whereType<Map>()
                  .map((e) => Map<String, String>.from(e))
                  .toList() ??
              const [],
        );
      case 'revoke':
        return RevokeMessage(a: json['a'] as String, b: json['b'] as String);
      case 'ping':
        return const PingMessage();
      case 'pong':
        return const PongMessage();
      case 'bye':
        return ByeMessage(
          reason: ByeReason.values.firstWhere(
            (r) => r.name == json['reason'],
            orElse: () => ByeReason.disconnect,
          ),
        );
      default:
        throw StateError('unknown message type: $type');
    }
  }
}
