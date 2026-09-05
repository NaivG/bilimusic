import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/lan_sync/services/lan_sync_service.dart';

/// 对端列表流（已发现的所有设备，含未配对）。
final peersProvider = StreamProvider<List<PeerDevice>>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.peerList;
});

// TODO(未实现功能): 远端「现在播放」接收链尚无任何 UI 消费（接收端在
// LanSyncService._handleState/_handlePlaylist），属未完成的新功能，暂保留；
// 实现「查看对端播放」后接入，届时仍未用可整链删除。
/// 当前对端推送的"现在播放"。
final remoteNowPlayingProvider = StreamProvider<RemoteNowPlaying?>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.remoteNowPlaying;
});

// TODO(未实现功能): sync_page 直接订阅 svc.pinRequests，此 provider 暂无消费方，
// 属未完成的新功能，暂保留。
/// 被动方收到的 PIN 请求流。
final pinRequestsProvider = StreamProvider<PinRequest>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.pinRequests;
});
