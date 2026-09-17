import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/lan_sync/services/lan_sync_service.dart';

/// 对端列表流（已发现的所有设备，含未配对）。
final peersProvider = StreamProvider<List<PeerDevice>>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.peerList;
});

/// 组内已建立 TCP 会话的对端（含公共只读连接），按名称排序。
///
/// 「组」= 当前与本机握过手的设备集合；已配对但未连接的成员不在此列，
/// 它们在设备管理页（LanSyncPage）里以"未连接"呈现。
final connectedPeersProvider = Provider<List<PeerDevice>>((ref) {
  final peers = ref.watch(peersProvider).asData?.value ?? const <PeerDevice>[];
  return peers.where((p) => p.isConnected).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

/// 当前对端推送的「正在播放」（最近一次，单值流）。
///
/// 多设备同时在线时会互相覆盖，只适合"最近一台"的展示；
/// 组内每台设备各在放什么由 [remoteNowPlayingMapProvider] 按 peerId 归并。
final remoteNowPlayingProvider = StreamProvider<RemoteNowPlaying?>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.remoteNowPlaying;
});

/// peerId → 该对端最近一次推送的「正在播放」快照。
///
/// 同步面板的远端详情数据源。对端断开后其条目被剔除，避免面板残留上一轮的
/// 旧快照（服务层的 `_lastRemoteByPeer` 会保留到下次重连为止）。
class _RemoteNowPlayingMapWatcher
    extends Notifier<Map<String, RemoteNowPlaying>> {
  @override
  Map<String, RemoteNowPlaying> build() {
    ref.listen<AsyncValue<RemoteNowPlaying?>>(remoteNowPlayingProvider, (
      _,
      next,
    ) {
      final remote = next.asData?.value;
      if (remote == null) return;
      state = {...state, remote.peerId: remote};
    });
    ref.listen<AsyncValue<List<PeerDevice>>>(peersProvider, (_, next) {
      final peers = next.asData?.value;
      if (peers == null) return;
      _retainConnected(peers);
    });
    return const {};
  }

  void _retainConnected(List<PeerDevice> peers) {
    final online = {
      for (final p in peers)
        if (p.isConnected) p.id,
    };
    if (state.keys.every(online.contains)) return;
    state = {
      for (final entry in state.entries)
        if (online.contains(entry.key)) entry.key: entry.value,
    };
  }
}

/// 组内各对端的「正在播放」快照表（同步面板的远端详情数据源）。
final remoteNowPlayingMapProvider =
    NotifierProvider<
      _RemoteNowPlayingMapWatcher,
      Map<String, RemoteNowPlaying>
    >(_RemoteNowPlayingMapWatcher.new);

// TODO(未实现功能): sync_page 直接订阅 svc.pinRequests，此 provider 暂无消费方，
// 属未完成的新功能，暂保留。
/// 被动方收到的 PIN 请求流。
final pinRequestsProvider = StreamProvider<PinRequest>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.pinRequests;
});
