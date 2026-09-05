import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bilimusic/models/sync/lan_sync_mode.dart';
import 'package:bilimusic/models/sync/peer_device.dart';

/// 设备列表中按"已配对 × 已连接"划分的 4 种状态。
enum _TileState {
  /// 未配对（仅被发现）。
  unpaired,

  /// 已配对但当前无 TCP 会话。
  pairedDisconnected,

  /// 已连接 · 私有模式。
  connectedPrivate,

  /// 已连接 · 公共模式（公共连接无配对概念）。
  connectedPublic,
}

_TileState _resolveState(PeerDevice peer) {
  if (peer.isConnected) {
    return peer.mode.acceptsPrivate
        ? _TileState.connectedPrivate
        : _TileState.connectedPublic;
  }
  return peer.isPaired ? _TileState.pairedDisconnected : _TileState.unpaired;
}

/// 设备列表中的单行：图标 + 名称/平台 + 状态徽标 + 右侧动作。
class DeviceTile extends StatelessWidget {
  final PeerDevice peer;
  final bool requiresPrivate;
  final VoidCallback? onPairTap;
  final VoidCallback? onConnectPairedTap;
  final VoidCallback? onDisconnectTap;
  final VoidCallback? onUnpairTap;
  final VoidCallback? onTap;

  const DeviceTile({
    super.key,
    required this.peer,
    this.requiresPrivate = true,
    this.onPairTap,
    this.onConnectPairedTap,
    this.onDisconnectTap,
    this.onUnpairTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = _resolveState(peer);
    final (statusText, statusColor) = _statusFor(state, colorScheme);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: _platformColor(peer.platform).withValues(alpha: 0.15),
        foregroundColor: _platformColor(peer.platform),
        child: Icon(_platformIcon(peer.platform), size: 20),
      ),
      title: Row(
        children: [
          Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(width: 6),
          if (peer.mode != LanSyncMode.off) ...[_ModeChip(peer.mode)],
        ],
      ),
      subtitle: Row(
        children: [
          Text(
            _platformLabel(peer.platform),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          _StatusDot(color: statusColor),
          const SizedBox(width: 4),
          Text(statusText, style: TextStyle(fontSize: 12, color: statusColor)),
        ],
      ),
      trailing: _buildTrailing(state),
    );
  }

  (String, Color) _statusFor(_TileState state, ColorScheme cs) {
    switch (state) {
      case _TileState.unpaired:
        return ('未配对', cs.onSurfaceVariant);
      case _TileState.pairedDisconnected:
        return ('未连接', Colors.amber);
      case _TileState.connectedPrivate || _TileState.connectedPublic:
        return ('已连接', Colors.green);
    }
  }

  Widget? _buildTrailing(_TileState state) {
    switch (state) {
      case _TileState.unpaired:
        if (onPairTap == null) return null;
        return FilledButton.tonal(
          onPressed: onPairTap,
          child: Text(requiresPrivate ? '配对' : '连接'),
        );
      case _TileState.pairedDisconnected:
        if (onConnectPairedTap == null) return null;
        return FilledButton.tonal(
          onPressed: onConnectPairedTap,
          child: const Text('连接'),
        );
      case _TileState.connectedPrivate:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: '断开连接',
              onPressed: onDisconnectTap,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '取消配对',
              onPressed: onUnpairTap,
            ),
          ],
        );
      case _TileState.connectedPublic:
        return IconButton(
          icon: const Icon(Icons.link_off),
          tooltip: '断开连接',
          onPressed: onDisconnectTap,
        );
    }
  }
}

class _ModeChip extends StatelessWidget {
  final LanSyncMode mode;
  const _ModeChip(this.mode);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (mode) {
      LanSyncMode.private => (Icons.lock_outline, colorScheme.secondary),
      LanSyncMode.public => (Icons.public, colorScheme.tertiary),
      LanSyncMode.off => (Icons.power_off, colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            modeShortLabel(mode),
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'android' => Icons.android,
    'ios' => Icons.phone_iphone,
    'windows' => Icons.laptop_windows,
    'macos' => Icons.laptop_mac,
    'linux' => Icons.computer,
    _ => Icons.device_unknown,
  };
}

String _platformLabel(String platform) {
  return switch (platform) {
    'android' => 'Android',
    'ios' => 'iOS',
    'windows' => 'Windows',
    'macos' => 'macOS',
    'linux' => 'Linux',
    _ => platform,
  };
}

Color _platformColor(String platform) {
  return switch (platform) {
    'android' => Colors.green,
    'ios' => Colors.blueGrey,
    'windows' => Colors.blue,
    'macos' => Colors.indigo,
    'linux' => Colors.orange,
    _ => Colors.grey,
  };
}

/// 把一段字符串复制到剪贴板。
Future<void> copyToClipboard(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
}
