import 'dart:io';

import 'package:bilimusic/models/sync/lan_sync_mode.dart';

/// 局域网内一个对端设备的快照。
///
/// 由 mDNS discovery 或主动 TCP connect 产生；字段不可变，
/// 状态变化通过 `copyWith` 派生新实例。
class PeerDevice {
  /// 设备 UUID（来自对端的 mDNS TXT 或 hello 消息）。
  final String id;

  /// 用户可见的设备名。
  final String name;

  /// 平台标识：`android` / `windows` / `macos` / `linux` / `ios`。
  final String platform;

  /// 对端在 mDNS TXT 中声明的模式。
  final LanSyncMode mode;

  /// 最近一次 mDNS 解析到的 IP。
  final InternetAddress host;

  /// TCP 端口（默认 47890）。
  final int port;

  /// 最近一次见到的时间。
  final DateTime lastSeen;

  /// 是否已与本端完成 PIN 配对（持有有效 token）。
  final bool isPaired;

  /// 当前是否已建立 TCP 会话。
  final bool isConnected;

  const PeerDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.mode,
    required this.host,
    required this.port,
    required this.lastSeen,
    this.isPaired = false,
    this.isConnected = false,
  });

  PeerDevice copyWith({
    String? name,
    LanSyncMode? mode,
    InternetAddress? host,
    int? port,
    DateTime? lastSeen,
    bool? isPaired,
    bool? isConnected,
  }) {
    return PeerDevice(
      id: id,
      name: name ?? this.name,
      platform: platform,
      mode: mode ?? this.mode,
      host: host ?? this.host,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      isPaired: isPaired ?? this.isPaired,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PeerDevice && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
