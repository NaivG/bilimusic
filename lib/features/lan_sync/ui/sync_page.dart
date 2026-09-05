import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/sync/lan_sync_mode.dart';
import 'package:bilimusic/models/sync/peer_device.dart';
import 'package:bilimusic/providers/lan_sync_providers.dart';
import 'package:bilimusic/providers/settings_provider.dart';
import 'package:bilimusic/services/sync/device_identity.dart';
import 'package:bilimusic/services/sync/lan_sync_service.dart';
import 'package:bilimusic/services/sync/pairing_service.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/pages/sync/device_tile.dart';
import 'package:bilimusic/pages/sync/pair_qr_dialog.dart';
import 'package:bilimusic/pages/sync/pair_request_dialog.dart';

/// 局域网同步设备管理页。
///
/// 三段式布局：
/// 1. 本机信息卡：设备名、平台、ID、当前 PIN
/// 2. "已配对"列表（含已连接 / 未连接）
/// 3. "可发现"列表（未配对的设备）
///
/// 顶部操作：模式切换、显示 QR、设置设备名。
class LanSyncPage extends ConsumerStatefulWidget {
  const LanSyncPage({super.key});

  @override
  ConsumerState<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends ConsumerState<LanSyncPage> {
  StreamSubscription<PinRequest>? _pinSub;

  @override
  void initState() {
    super.initState();
    // 监听 PIN 请求：弹"对方请求配对"对话框
    _pinSub = ref
        .read(lanSyncServiceProvider)
        .pinRequests
        .listen(_onPinRequest);
  }

  @override
  void dispose() {
    _pinSub?.cancel();
    super.dispose();
  }

  void _onPinRequest(PinRequest req) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) =>
          PairRequestDialog(peerId: req.peerId, peerName: req.peerName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final identity = ref.watch(deviceIdentityProvider);
    final pairing = ref.watch(pairingServiceProvider);
    final peersAsync = ref.watch(peersProvider);

    final mode = LanSyncMode.fromString(settings.lanSyncMode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('局域网同步'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        forceMaterialTransparency: true,
      ),
      body: mode == LanSyncMode.off
          ? const _OffModeHint()
          : ListView(
              children: [
                _SelfCard(
                  name: identity.name,
                  platform: identity.platform,
                  id: identity.id,
                  pin: pairing.currentPin,
                  mode: mode,
                  onChangeName: () => _editDeviceName(identity.name),
                  onShowQr: () => _showQr(identity, pairing),
                  onRotatePin: () => _rotatePin(pairing),
                ),
                const SizedBox(height: 12),
                peersAsync.when(
                  data: (peers) => _PeerSection(
                    peers: peers,
                    localMode: mode,
                    onPair: (peer, pin) => _startPairWithDialog(peer, pin),
                    onConnectPublic: (peer) =>
                        ref.read(lanSyncServiceProvider).connectPublic(peer),
                    onConnectPaired: (peer) =>
                        ref.read(lanSyncServiceProvider).connectPaired(peer),
                    onDisconnect: (id) =>
                        ref.read(lanSyncServiceProvider).disconnect(id),
                    onUnpair: (id) =>
                        ref.read(lanSyncServiceProvider).unpair(id),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('加载失败: $e'),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Future<void> _editDeviceName(String current) async {
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('修改设备名'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(
              hintText: '对方看到的名称',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    // controller.dispose();
    if (newName == null || newName.trim().isEmpty) return;
    await ref.read(deviceIdentityProvider).setName(newName.trim());
    // 同步到 SettingsManager（让持久化覆盖 LAN 自身）
    await ref
        .read(settingsProvider.notifier)
        .setLanSyncDeviceName(newName.trim());
    if (mounted) setState(() {});
  }

  Future<void> _showQr(DeviceIdentity identity, PairingService pairing) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => PairQrDialog(
        deviceId: identity.id,
        deviceName: identity.name,
        pin: pairing.currentPin,
      ),
    );
  }

  Future<void> _rotatePin(PairingService pairing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置 PIN？'),
        content: const Text('重置后其他设备需要重新输入新 PIN 才能连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await pairing.rotatePin();
      if (mounted) setState(() {});
    }
  }

  /// 主动发起配对：发起后台连接 → 弹"等待对方响应"模态框 → 监听结果关闭。
  Future<void> _startPairWithDialog(PeerDevice peer, String pin) async {
    final svc = ref.read(lanSyncServiceProvider);
    unawaited(svc.pairWith(peer, pin));
    if (!mounted) return;
    final result = await showDialog<PairingResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WaitingForPeerDialog(peer: peer),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result?.ok == true) {
      messenger.showSnackBar(SnackBar(content: Text('与 ${peer.name} 配对成功')));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('与 ${peer.name} 配对失败：${result?.reason ?? "对方无响应"}'),
        ),
      );
    }
  }
}

class _OffModeHint extends StatelessWidget {
  const _OffModeHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              '局域网同步已关闭',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '前往"设置 → 局域网同步"开启后才能发现其他设备。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfCard extends StatelessWidget {
  final String name;
  final String platform;
  final String id;
  final String pin;
  final LanSyncMode mode;
  final VoidCallback onChangeName;
  final VoidCallback onShowQr;
  final VoidCallback onRotatePin;

  const _SelfCard({
    required this.name,
    required this.platform,
    required this.id,
    required this.pin,
    required this.mode,
    required this.onChangeName,
    required this.onShowQr,
    required this.onRotatePin,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smartphone, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '本机',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  _modeLabel(mode),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Field(label: '设备名', value: name, onEdit: onChangeName),
            const SizedBox(height: 6),
            _Field(label: '平台', value: platform),
            const SizedBox(height: 6),
            _Field(label: 'ID', value: id, monospace: true, copyValue: id),
            const SizedBox(height: 6),
            _Field(
              label: 'PIN',
              value: pin.isEmpty ? '未加载' : pin,
              monospace: true,
              copyValue: pin,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '重置 PIN',
                    onPressed: onRotatePin,
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    tooltip: '显示二维码',
                    onPressed: onShowQr,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _modeLabel(LanSyncMode m) {
    return switch (m) {
      LanSyncMode.off => '已关闭',
      LanSyncMode.private => '私有模式',
      LanSyncMode.public => '公共模式',
    };
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
  final String? copyValue;
  final VoidCallback? onEdit;
  final Widget? trailing;

  const _Field({
    required this.label,
    required this.value,
    this.monospace = false,
    this.copyValue,
    this.onEdit,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: monospace ? 13 : 14,
              fontFamily: monospace ? 'monospace' : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
          ),
        if (copyValue != null && copyValue!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => copyToClipboard(context, copyValue!),
          ),
        ?trailing,
      ],
    );
  }
}

/// 主动方（A）发起配对后的"等待 B 端响应"模态框。
///
/// 监听 [LanSyncService.pairingResults] 流；当收到对端 peerId 匹配的结果
/// （成功 / 失败 / 取消）时自动关闭并把 [PairingResult] 返回给调用方。
class _WaitingForPeerDialog extends ConsumerStatefulWidget {
  final PeerDevice peer;
  const _WaitingForPeerDialog({required this.peer});

  @override
  ConsumerState<_WaitingForPeerDialog> createState() =>
      _WaitingForPeerDialogState();
}

class _WaitingForPeerDialogState extends ConsumerState<_WaitingForPeerDialog> {
  StreamSubscription<PairingResult>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(lanSyncServiceProvider).pairingResults.listen(_onResult);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onResult(PairingResult r) {
    if (r.peerId != widget.peer.id) return;
    if (!mounted) return;
    Navigator.pop(context, r);
  }

  void _onCancel() {
    ref.read(lanSyncServiceProvider).cancelInitiatedPairing(widget.peer.id);
    // cancelInitiatedPairing 自身会推一条 PairingResult 触发关闭，无需手动 pop
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('等待对方响应'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在等待 ${widget.peer.name} 在其设备上确认配对…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '对方需要在弹窗中输入你的 6 位 PIN 后双方才配对成功。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [TextButton(onPressed: _onCancel, child: const Text('取消配对'))],
    );
  }
}

class _PeerSection extends StatelessWidget {
  final List<PeerDevice> peers;
  final LanSyncMode localMode;
  final void Function(PeerDevice peer, String pin) onPair;
  final void Function(PeerDevice peer) onConnectPublic;
  final void Function(PeerDevice peer) onConnectPaired;
  final void Function(String peerId) onDisconnect;
  final void Function(String peerId) onUnpair;

  const _PeerSection({
    required this.peers,
    required this.localMode,
    required this.onPair,
    required this.onConnectPublic,
    required this.onConnectPaired,
    required this.onDisconnect,
    required this.onUnpair,
  });

  @override
  Widget build(BuildContext context) {
    final paired = peers.where((p) => p.isPaired).toList();
    final unpaired = peers.where((p) => !p.isPaired).toList();

    if (peers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '暂未发现局域网内的其他 BiliMusic 设备',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '请确认所有设备连接到同一 WiFi/路由器',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (paired.isNotEmpty) ...[
          const _SectionHeader('已配对'),
          ...paired.map((p) {
            // 已配对但当前离线(mDNS lost 但 isPaired 仍为 true)时 p.host
            // 仍指向最后一次见到时的地址,点「连接」由服务层负责 connect 失败处理
            return DeviceTile(
              peer: p,
              onConnectPairedTap: p.isConnected
                  ? null
                  : () => onConnectPaired(p),
              onDisconnectTap: p.isConnected
                  ? () => _confirmDisconnect(context, p, onDisconnect)
                  : null,
              onUnpairTap: p.isConnected
                  ? () => _confirmUnpair(context, p, onUnpair)
                  : null,
            );
          }),
        ],
        if (unpaired.isNotEmpty) ...[
          const _SectionHeader('可发现'),
          ...unpaired.map((p) {
            final requiresPrivate =
                localMode.acceptsPrivate && p.mode.acceptsPrivate;
            // 公共模式已连接的对端会落到这里(无配对概念),
            // 同样需要能断开 → 总是注入 onDisconnectTap,DeviceTile 内部按状态分发
            return DeviceTile(
              peer: p,
              requiresPrivate: requiresPrivate,
              onPairTap: () => _onUnpairedTap(
                context: context,
                peer: p,
                requiresPrivate: requiresPrivate,
                onPair: onPair,
                onConnectPublic: onConnectPublic,
              ),
              onDisconnectTap: p.isConnected
                  ? () => _confirmDisconnect(context, p, onDisconnect)
                  : null,
            );
          }),
        ],
      ],
    );
  }

  Future<void> _onUnpairedTap({
    required BuildContext context,
    required PeerDevice peer,
    required bool requiresPrivate,
    required void Function(PeerDevice, String) onPair,
    required void Function(PeerDevice) onConnectPublic,
  }) async {
    if (requiresPrivate) {
      await _promptPin(context, peer, onPair);
    } else {
      onConnectPublic(peer);
    }
  }

  Future<void> _confirmDisconnect(
    BuildContext context,
    PeerDevice peer,
    void Function(String) onDisconnect,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开连接？'),
        content: Text('确定断开与 "${peer.name}" 的连接？\n配对信息会保留,可在列表中再次连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (ok == true) onDisconnect(peer.id);
  }

  Future<void> _confirmUnpair(
    BuildContext context,
    PeerDevice peer,
    void Function(String) onUnpair,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消配对？'),
        content: Text('确定取消与 "${peer.name}" 的配对？\n需要重新输入 PIN 才能再次连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消配对'),
          ),
        ],
      ),
    );
    if (ok == true) onUnpair(peer.id);
  }

  Future<void> _promptPin(
    BuildContext context,
    PeerDevice peer,
    void Function(PeerDevice, String) onPair,
  ) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('与 ${peer.name} 配对'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请输入对方设备上的 6 位 PIN：',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '6 位数字',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('配对'),
          ),
        ],
      ),
    );
    // controller.dispose();
    if (pin == null || pin.length != 6) return;
    onPair(peer, pin);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 通过 ShellPageManager 弹出 LanSyncPage 的工具方法（供 settings/profile 入口调用）。
void openLanSyncPage() {
  ShellPageManager.instance.push(ShellPage.lanSync);
}
