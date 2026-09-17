import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/peer_device.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/lan_sync/services/lan_sync_service.dart';

/// 同步面板的远端快照表：按 peerId 归并 + 断开后剔除。
///
/// 两个数据源 provider 都被替换成内存流，因此不会真的启动 LAN 服务。
void main() {
  late StreamController<RemoteNowPlaying?> remotes;
  late StreamController<List<PeerDevice>> peers;
  late ProviderContainer container;

  setUp(() {
    remotes = StreamController<RemoteNowPlaying?>.broadcast();
    peers = StreamController<List<PeerDevice>>.broadcast();
    container = ProviderContainer(
      overrides: [
        remoteNowPlayingProvider.overrideWith((ref) => remotes.stream),
        peersProvider.overrideWith((ref) => peers.stream),
      ],
    );
    // 模拟同步面板打开时的订阅（面板用 ref.watch 持有这张表）。
    container.listen(remoteNowPlayingMapProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await remotes.close();
    await peers.close();
  });

  test('同一对端的新快照覆盖旧值，不同对端各自归并', () async {
    remotes.add(_remote('peer-a', '歌 1'));
    await pumpEventQueue();
    expect(_snapshots(container)['peer-a']?.music?.title, '歌 1');

    remotes.add(_remote('peer-a', '歌 2'));
    await pumpEventQueue();
    expect(_snapshots(container), hasLength(1));
    expect(_snapshots(container)['peer-a']?.music?.title, '歌 2');

    remotes.add(_remote('peer-b', '歌 3'));
    await pumpEventQueue();
    expect(_snapshots(container), hasLength(2));
    expect(_snapshots(container)['peer-b']?.music?.title, '歌 3');
  });

  test('对端断开后其快照被剔除，仍在线的不受影响', () async {
    remotes.add(_remote('peer-a', '歌 1'));
    remotes.add(_remote('peer-b', '歌 2'));
    await pumpEventQueue();
    expect(_snapshots(container), hasLength(2));

    peers.add([_peer('peer-a', connected: false), _peer('peer-b')]);
    await pumpEventQueue();

    expect(_snapshots(container).keys, ['peer-b']);
  });

  test('connectedPeersProvider 只保留在线设备并按名称排序', () async {
    container.listen(connectedPeersProvider, (_, _) {});
    peers.add([
      _peer('peer-b', name: '乙设备'),
      _peer('peer-a', name: '甲设备'),
      _peer('peer-c', name: '丙设备', connected: false),
    ]);
    await pumpEventQueue();

    final connected = container.read(connectedPeersProvider);
    expect(connected.map((p) => p.name), ['乙设备', '甲设备']);
  });
}

Map<String, RemoteNowPlaying> _snapshots(ProviderContainer container) =>
    container.read(remoteNowPlayingMapProvider);

RemoteNowPlaying _remote(String peerId, String title) {
  return RemoteNowPlaying(
    peerId: peerId,
    peerName: peerId,
    music: Music(
      id: title,
      title: title,
      artist: 'artist',
      album: 'album',
      coverUrl: '',
      duration: const Duration(minutes: 3),
      audioUrl: '',
    ),
    position: const Duration(seconds: 30),
    isPlaying: true,
    queue: const [],
    currentIndex: 0,
  );
}

PeerDevice _peer(String id, {String? name, bool connected = true}) {
  return PeerDevice(
    id: id,
    name: name ?? id,
    platform: 'windows',
    mode: LanSyncMode.private,
    host: InternetAddress.loopbackIPv4,
    port: 47890,
    lastSeen: DateTime(2026),
    isPaired: true,
    isConnected: connected,
  );
}
