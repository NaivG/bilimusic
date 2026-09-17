import 'package:flutter/material.dart';

import 'package:bilimusic/domain/lan_sync_mode.dart';

/// LAN 设备的平台 / 模式视觉映射。
///
/// 设备列表（[DeviceTile]）与同步面板共用，避免两处各写一份 switch。

IconData platformIcon(String platform) {
  return switch (platform) {
    'android' => Icons.android,
    'ios' => Icons.phone_iphone,
    'windows' => Icons.laptop_windows,
    'macos' => Icons.laptop_mac,
    'linux' => Icons.computer,
    _ => Icons.device_unknown,
  };
}

String platformLabel(String platform) {
  return switch (platform) {
    'android' => 'Android',
    'ios' => 'iOS',
    'windows' => 'Windows',
    'macos' => 'macOS',
    'linux' => 'Linux',
    _ => platform,
  };
}

Color platformColor(String platform) {
  return switch (platform) {
    'android' => Colors.green,
    'ios' => Colors.blueGrey,
    'windows' => Colors.blue,
    'macos' => Colors.indigo,
    'linux' => Colors.orange,
    _ => Colors.grey,
  };
}

/// 设备模式徽标：私有 / 公共 / 已关闭。
class DeviceModeChip extends StatelessWidget {
  final LanSyncMode mode;
  const DeviceModeChip(this.mode, {super.key});

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
