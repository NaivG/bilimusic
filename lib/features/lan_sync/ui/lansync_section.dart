import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/models/sync/lan_sync_mode.dart';
import 'package:bilimusic/pages/sync_page.dart';
import 'package:bilimusic/providers/settings_provider.dart';
import 'package:bilimusic/utils/platform_helper.dart';

/// profile_page 上的"局域网同步"行。
///
/// UI 风格与 RoamSection 一致：圆角图标块 + 标题 + trailing。
/// 入口直接 push `ShellPage.lanSync`（在 lan_sync_page 里再处理 mode=off 的提示）。
class LanSyncSection extends ConsumerWidget {
  const LanSyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Web 不支持 UDP/mDNS，直接隐藏入口
    if (PlatformHelper.isWeb) return const SizedBox.shrink();

    final mode = LanSyncMode.fromString(
      ref.watch(settingsProvider).lanSyncMode,
    );
    final modeLabel = _modeLabel(mode);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.wifi_tethering, color: Colors.teal),
      ),
      title: const Text('局域网同步'),
      subtitle: mode == LanSyncMode.off ? null : Text(modeLabel),
      trailing: const Icon(Icons.arrow_forward_ios),
      onTap: openLanSyncPage,
    );
  }

  static String _modeLabel(LanSyncMode m) {
    return switch (m) {
      LanSyncMode.off => '',
      LanSyncMode.private => '私有模式 · 配对后可双向同步',
      LanSyncMode.public => '公共模式 · 仅对局域网暴露正在播放',
    };
  }
}
