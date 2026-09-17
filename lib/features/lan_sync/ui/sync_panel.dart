import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/lan_sync/models/sync_message.dart';
import 'package:bilimusic/features/lan_sync/services/lan_sync_service.dart';
import 'package:bilimusic/features/lan_sync/ui/device_visuals.dart';
import 'package:bilimusic/features/lan_sync/ui/sync_page.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/utils/dialog_helpers.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 打开同步面板（底部弹出）。
///
/// 面板与入口解耦：当前从播放详情页「更多」操作单进入（临时接线，
/// 见 [syncPanelSheetAction]），后续挪到常驻入口时本函数直接复用。
Future<void> showSyncPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.grey[900],
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const SyncPanel(),
  );
}

/// 详情页「更多」操作单里的同步面板入口。
///
/// [onlinePeers] 直接把"组内有几台在线"写在标签上，省得用户点进去才知道；
/// 调用点在 build 之外（操作单回调），只能 `ref.read` 取一次快照：
/// 对端流尚未被订阅过时是 0，此时标签退化成「同步面板」。
// TODO(临时接线): 等同步面板有了自己的常驻入口（播放页按钮 / 侧边栏）后删除。
SheetAction syncPanelSheetAction(BuildContext context, {int onlinePeers = 0}) {
  return SheetAction(
    icon: Icons.sync,
    label: onlinePeers > 0 ? '同步面板 · $onlinePeers 台在线' : '同步面板',
    onTap: () => showSyncPanel(context),
  );
}

/// 同步面板：显示远端（私有组）详情与控制。
///
/// 三段式内容：
/// 1. 组概览：本机设备 + 组内在线成员（可切换查看某台）
/// 2. 远端详情：选中设备推送的播放快照（曲目 / 进度 / 队列位置）
/// 3. 控制：
///    - 本机为主控端 → 遥控对端播放、推送本机曲目（对端会先退出自己的漫游）
///    - 本机为被控端 → 跟随此设备（本机先退出漫游，再跟随对端队列）
///    - 断开连接
///
/// 数据源：[connectedPeersProvider]（在线成员）与 [remoteNowPlayingMapProvider]
/// （各成员最近一次推送的快照）。
class SyncPanel extends ConsumerStatefulWidget {
  const SyncPanel({super.key});

  @override
  ConsumerState<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends ConsumerState<SyncPanel> {
  /// 当前查看的对端 id；null 表示未选择（回落到组内第一台）。
  String? _selectedPeerId;

  /// 远端只在自己状态变化时广播，进度条要看起来连续就得本地补时：
  /// 播放中每秒重建一次，数值仍是"最后一次快照 + 本地经过时间"。
  Timer? _ticker;

  /// 拖动中的 seek 目标值（松手发送指令后清空）。
  double? _seekDraft;

  /// 最近一次快照对象及其到达时间，用于推算当前进度。
  RemoteNowPlaying? _stampedRemote;
  DateTime _stampAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 面板打开时向组内所有在线设备索取一次快照：对端平时只在变化时广播，
    // 刚打开面板可能一条都没有（公共只读会话会被服务层拒绝，无副作用）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final svc = ref.read(lanSyncServiceProvider);
      for (final peer in ref.read(connectedPeersProvider)) {
        svc.requestRemoteState(peer.id);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = LanSyncMode.fromString(
      ref.watch(settingsProvider).lanSyncMode,
    );
    final identity = ref.watch(deviceIdentityProvider);
    final peers = ref.watch(connectedPeersProvider);
    final remotes = ref.watch(remoteNowPlayingMapProvider);

    final selected = _resolveSelected(peers);
    final remote = selected == null ? null : remotes[selected.id];
    _stamp(remote);
    _syncTicker(remote?.isPlaying ?? false);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            _PanelHeader(
              mode: mode,
              localName: identity.name,
              onlineCount: peers.length,
              onManageDevices: _openDeviceManager,
            ),
            if (selected != null)
              _MemberChips(
                peers: peers,
                remotes: remotes,
                selectedId: selected.id,
                onSelect: _selectPeer,
              ),
            const Divider(height: 1, color: Colors.white12),
            Flexible(child: _buildBody(mode, selected, remote)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    LanSyncMode mode,
    PeerDevice? peer,
    RemoteNowPlaying? remote,
  ) {
    if (mode == LanSyncMode.off) {
      return _PanelHint(
        icon: Icons.wifi_off,
        title: '局域网同步已关闭',
        description: '在「设置 → 局域网同步」里选私有模式后，才能与其它设备互相同步与控制。',
        actionLabel: '设备管理',
        onAction: _openDeviceManager,
      );
    }
    if (peer == null) {
      return _PanelHint(
        icon: Icons.devices_other,
        title: '组内暂无在线设备',
        description: '同一 WiFi 下已配对的设备会自动连接；未配对的设备请先在设备管理页完成配对。',
        actionLabel: '设备管理',
        onAction: _openDeviceManager,
      );
    }

    final canControl = _canControl(peer);
    final music = remote?.music;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _DeviceSummary(peer: peer),
        const SizedBox(height: 14),
        if (remote == null || music == null)
          _NoSnapshotHint(onRefresh: () => _requestState(peer.id))
        else ...[
          _RemoteNowPlayingCard(
            remote: remote,
            position: _displayPosition(remote),
            canControl: canControl,
            seekDraft: _seekDraft,
            onSeekPreview: (value) => setState(() => _seekDraft = value),
            onSeekCommit: (value) {
              setState(() => _seekDraft = null);
              _send(
                peer.id,
                CmdActions.seek,
                payload: {'positionMs': value.round()},
              );
            },
          ),
          const SizedBox(height: 8),
          _RemoteTransport(
            enabled: canControl,
            playing: remote.isPlaying,
            onPrevious: () => _send(peer.id, CmdActions.prev),
            onPlayPause: () => _send(
              peer.id,
              remote.isPlaying ? CmdActions.pause : CmdActions.resume,
            ),
            onNext: () => _send(peer.id, CmdActions.next),
          ),
        ],
        const SizedBox(height: 18),
        _PanelActions(
          peerName: peer.name,
          hasRemoteQueue: (remote?.queue.isNotEmpty ?? false),
          canControl: canControl,
          onFollow: remote == null ? null : () => _followRemote(peer, remote),
          onPush: () => _pushCurrentMusic(peer),
          onDisconnect: () => _confirmDisconnect(peer),
        ),
        if (remote != null && remote.queue.isNotEmpty) ...[
          const SizedBox(height: 18),
          _RemoteQueue(
            remote: remote,
            enabled: canControl,
            onPick: (index) =>
                _send(peer.id, CmdActions.playAt, payload: {'index': index}),
          ),
        ],
      ],
    );
  }

  // ==================== 状态与动作 ====================

  PeerDevice? _resolveSelected(List<PeerDevice> peers) {
    if (peers.isEmpty) return null;
    for (final peer in peers) {
      if (peer.id == _selectedPeerId) return peer;
    }
    return peers.first;
  }

  /// 遥控需要"私有 + 已完成 token 握手"的会话。UI 只能近似判断
  /// （已配对 + 在线 + 对端私有模式），真正判定在
  /// [LanSyncService.sendRemoteCommand]：返回 false 时按"未就绪"提示。
  bool _canControl(PeerDevice peer) =>
      peer.isConnected && peer.isPaired && peer.mode.acceptsPrivate;

  void _stamp(RemoteNowPlaying? remote) {
    if (remote == null || identical(remote, _stampedRemote)) return;
    _stampedRemote = remote;
    _stampAt = DateTime.now();
  }

  /// 快照里的位置是"对端发送那一刻"的值，播放中时按本地经过时间外推。
  Duration _displayPosition(RemoteNowPlaying remote) {
    if (!remote.isPlaying) return remote.position;
    final estimated = remote.position + DateTime.now().difference(_stampAt);
    final total = remote.music?.duration;
    if (total != null && estimated > total) return total;
    return estimated;
  }

  void _syncTicker(bool needed) {
    if (!needed) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _selectPeer(PeerDevice peer) {
    setState(() {
      _selectedPeerId = peer.id;
      _seekDraft = null;
    });
    _requestState(peer.id);
  }

  void _requestState(String peerId) {
    ref.read(lanSyncServiceProvider).requestRemoteState(peerId);
  }

  /// 发送一条遥控指令；发不出去时明确提示，避免用户以为"按了没反应"。
  void _send(String peerId, String action, {Map<String, dynamic>? payload}) {
    final ok = ref
        .read(lanSyncServiceProvider)
        .sendRemoteCommand(peerId, action, payload: payload);
    if (ok || !mounted) return;
    _toast('指令未发送：该设备未处于私有连接状态');
  }

  /// 让本机跟随选中设备的队列播放。
  ///
  /// 方向：本机是**被控端**，对端是主控端。因此只对齐队列与曲目序号、不对齐
  /// 播放位置（快照里的 position 可能已经过期，硬 seek 反而更不同步），
  /// 并由 `adoptRemotePlaylist` 负责退出本机正在进行的漫游。
  Future<void> _followRemote(PeerDevice peer, RemoteNowPlaying remote) async {
    if (remote.queue.isEmpty) {
      _toast('该设备没有共享队列（公共只读连接），无法跟随');
      return;
    }
    final coordinator = ref.read(playerCoordinatorProvider);
    final wasRoaming = coordinator.isRoaming;
    await coordinator.adoptRemotePlaylist(
      songs: remote.queue,
      index: remote.currentIndex,
    );
    if (!mounted) return;
    _toast(
      '已跟随「${peer.name}」的队列（${remote.queue.length} 首）'
      '${wasRoaming ? '，已退出漫游' : ''}',
    );
  }

  /// 把本机当前曲目推送到对端播放。
  ///
  /// 方向：本机是**主控端**，对端是被控端；被控端会在收到该指令时先退出
  /// 自己的漫游（见 [LanSyncService] 的 cmd 处理），无需本机额外通知。
  Future<void> _pushCurrentMusic(PeerDevice peer) async {
    final music = ref.read(playerCoordinatorProvider).currentMusic;
    if (music == null) {
      _toast('本机当前没有播放中的曲目');
      return;
    }
    try {
      // 推送前补齐 cid，保证对端拿到即可播放。
      final detailed = await ref.read(apiServiceProvider).ensureCid(music);
      if (!mounted) return;
      final ok = ref
          .read(lanSyncServiceProvider)
          .pushMusicToPeer(peer.id, detailed);
      _toast(ok ? '已推送到「${peer.name}」：${detailed.title}' : '推送失败：该设备未处于私有连接状态');
    } catch (e) {
      if (mounted) _toast('推送失败：$e');
    }
  }

  Future<void> _confirmDisconnect(PeerDevice peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开连接？'),
        content: Text('确定断开与「${peer.name}」的连接？\n配对信息会保留，可在设备管理页再次连接。'),
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
    if (confirmed != true) return;
    await ref.read(lanSyncServiceProvider).disconnect(peer.id);
    if (!mounted) return;
    setState(() => _selectedPeerId = null);
    _toast('已断开与「${peer.name}」的连接');
  }

  /// 关闭面板并跳到设备管理页（配对、改设备名、看 PIN 都在那里）。
  void _openDeviceManager() {
    Navigator.pop(context);
    openLanSyncPage();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

// ==================== 结构件 ====================

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final LanSyncMode mode;
  final String localName;
  final int onlineCount;
  final VoidCallback onManageDevices;

  const _PanelHeader({
    required this.mode,
    required this.localName,
    required this.onlineCount,
    required this.onManageDevices,
  });

  @override
  Widget build(BuildContext context) {
    final summary = mode == LanSyncMode.off
        ? '本机「$localName」· 同步已关闭'
        : '${_modeLabel(mode)} · 本机「$localName」· $onlineCount 台在线';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.sync, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '同步面板',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onManageDevices,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('设备管理'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  static String _modeLabel(LanSyncMode m) {
    return switch (m) {
      LanSyncMode.off => '已关闭',
      LanSyncMode.private => '私有组',
      LanSyncMode.public => '公共只读',
    };
  }
}

/// 组员横向选择条：各在线对端（带播放状态指示），点击切换查看对象。
class _MemberChips extends StatelessWidget {
  final List<PeerDevice> peers;
  final Map<String, RemoteNowPlaying> remotes;
  final String selectedId;
  final void Function(PeerDevice peer) onSelect;

  const _MemberChips({
    required this.peers,
    required this.remotes,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final peer in peers) ...[
            _MemberChip(
              name: peer.name,
              icon: platformIcon(peer.platform),
              selected: peer.id == selectedId,
              remote: remotes[peer.id],
              onTap: () => onSelect(peer),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool selected;
  final RemoteNowPlaying? remote;
  final VoidCallback onTap;

  const _MemberChip({
    required this.name,
    required this.icon,
    required this.selected,
    required this.remote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final playing = remote?.isPlaying;
    final statusColor = switch (playing) {
      true => Colors.greenAccent,
      false => Colors.amber,
      null => Colors.white24,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white54 : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中设备的身份行：平台图标 + 名称 + 平台 + 模式徽标 + 连接状态。
class _DeviceSummary extends StatelessWidget {
  final PeerDevice peer;
  const _DeviceSummary({required this.peer});

  @override
  Widget build(BuildContext context) {
    final color = platformColor(peer.platform);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.18),
          foregroundColor: color,
          child: Icon(platformIcon(peer.platform), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                peer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${platformLabel(peer.platform)} · 已连接 · 最近 ${_formatClock(peer.lastSeen)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DeviceModeChip(peer.mode),
      ],
    );
  }

  static String _formatClock(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 远端「正在播放」卡片：封面 + 元信息 + 可拖动进度条。
class _RemoteNowPlayingCard extends StatelessWidget {
  final RemoteNowPlaying remote;
  final Duration position;
  final bool canControl;
  final double? seekDraft;
  final ValueChanged<double> onSeekPreview;
  final ValueChanged<double> onSeekCommit;

  const _RemoteNowPlayingCard({
    required this.remote,
    required this.position,
    required this.canControl,
    required this.seekDraft,
    required this.onSeekPreview,
    required this.onSeekCommit,
  });

  @override
  Widget build(BuildContext context) {
    final music = remote.music!;
    final total = music.duration;
    final totalMs = total?.inMilliseconds ?? 0;
    final currentMs = position.inMilliseconds.clamp(0, totalMs).toDouble();
    final draft = seekDraft;
    final shownMs = draft ?? currentMs;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverArt(url: music.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      music.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      music.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          remote.isPlaying
                              ? Icons.graphic_eq
                              : Icons.pause_circle_outline,
                          size: 14,
                          color: remote.isPlaying
                              ? Colors.greenAccent
                              : Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          remote.isPlaying ? '正在播放' : '已暂停',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                        if (remote.queue.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '队列 ${remote.currentIndex + 1}/${remote.queue.length}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: totalMs == 0 ? 0 : shownMs.toDouble(),
              max: totalMs == 0 ? 1 : totalMs.toDouble(),
              // 没有总时长 / 不可遥控时进度条只做展示。
              onChanged: (canControl && totalMs > 0) ? onSeekPreview : null,
              onChangeEnd: (canControl && totalMs > 0) ? onSeekCommit : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatDuration(Duration(milliseconds: shownMs.round())),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Text(
                  total == null ? '--:--' : formatDuration(total),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  final String url;
  const _CoverArt({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 64,
        child: url.isEmpty
            ? const _CoverFallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _CoverFallback(),
              ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: const Icon(Icons.music_note, color: Colors.white38, size: 24),
    );
  }
}

/// 远端传输控制：上一首 / 播放暂停 / 下一首。
class _RemoteTransport extends StatelessWidget {
  final bool enabled;
  final bool playing;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  const _RemoteTransport({
    required this.enabled,
    required this.playing,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 30,
          tooltip: '远端上一首',
          onPressed: enabled ? onPrevious : null,
          icon: const Icon(Icons.skip_previous),
          color: Colors.white,
          disabledColor: Colors.white24,
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          iconSize: 34,
          tooltip: playing ? '远端暂停' : '远端播放',
          onPressed: enabled ? onPlayPause : null,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 12),
        IconButton(
          iconSize: 30,
          tooltip: '远端下一首',
          onPressed: enabled ? onNext : null,
          icon: const Icon(Icons.skip_next),
          color: Colors.white,
          disabledColor: Colors.white24,
        ),
      ],
    );
  }
}

/// 面板动作区：推送本机曲目（本机为主控端）/ 跟随此设备（本机为被控端）/
/// 断开连接。
///
/// 按钮顺序按"控制方向"排：先"我把音乐送过去"，再"我跟着它听"——
/// 反过来容易被读成同义动作。
class _PanelActions extends StatelessWidget {
  final String peerName;
  final bool hasRemoteQueue;
  final bool canControl;
  final VoidCallback? onFollow;
  final VoidCallback onPush;
  final VoidCallback onDisconnect;

  const _PanelActions({
    required this.peerName,
    required this.hasRemoteQueue,
    required this.canControl,
    required this.onFollow,
    required this.onPush,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: canControl ? onPush : null,
              icon: const Icon(Icons.cast_connected, size: 18),
              label: const Text('推送本机曲目'),
            ),
            FilledButton.tonalIcon(
              onPressed: hasRemoteQueue ? onFollow : null,
              icon: const Icon(Icons.download_for_offline_outlined, size: 18),
              label: const Text('跟随此设备'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off, size: 18),
            label: Text('断开与「$peerName」的连接'),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
        ),
      ],
    );
  }
}

/// 远端共享队列（私有会话才有），点击切到对应对端曲目。
class _RemoteQueue extends StatelessWidget {
  final RemoteNowPlaying remote;
  final bool enabled;
  final void Function(int index) onPick;

  const _RemoteQueue({
    required this.remote,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '远端队列（${remote.queue.length} 首）',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: remote.queue.length,
            itemBuilder: (context, index) {
              final music = remote.queue[index];
              final isCurrent = index == remote.currentIndex;
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                enabled: enabled,
                leading: Icon(
                  isCurrent ? Icons.graphic_eq : Icons.music_note,
                  size: 16,
                  color: isCurrent ? Colors.greenAccent : Colors.white38,
                ),
                title: Text(
                  music.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? Colors.white : Colors.white70,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  music.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: music.duration == null
                    ? null
                    : Text(
                        formatDuration(music.duration!),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                onTap: enabled ? () => onPick(index) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 还没收到对端快照时的占位（可手动索取一次）。
class _NoSnapshotHint extends StatelessWidget {
  final VoidCallback onRefresh;
  const _NoSnapshotHint({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_sync_outlined, color: Colors.white38),
          const SizedBox(height: 8),
          const Text(
            '尚未收到该设备的播放快照',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            '对端只在播放状态变化时广播，可手动索取一次。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('索取快照'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// 空的组 / 未开启同步时的整页提示。
class _PanelHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  /// 可选的动作按钮（如"设备管理"）；为空时不渲染。
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PanelHint({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.tune, size: 16),
              label: Text(label),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}
