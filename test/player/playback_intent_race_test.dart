import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/play_mode.dart';
import 'package:bilimusic/features/player/logic/audio_effects_service.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/logic/notification_service.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/features/roam/roaming_service.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';

/// 只记录「谁被交给了播放器」，不建 libmpv。
class _FakeDualAudioService extends DualAudioService {
  final ValueNotifier<PlayMode> _mode = ValueNotifier(PlayMode.sequential);
  final List<String> played = [];

  @override
  ValueNotifier<PlayMode> get playMode => _mode;

  @override
  bool get isPlaying => false;

  @override
  bool get isFading => false;

  @override
  bool get isStandbyReady => false;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Duration get currentBufferedPosition => Duration.zero;

  @override
  void beginPlayRequest() {}

  @override
  Future<void> playActive(String url) async {
    played.add(url);
  }

  @override
  Future<void> stop() async {
    played.add('<stop>');
  }

  @override
  Future<void> discardStandby(String url) async {}

  @override
  Future<void> dispose() async {}
}

/// 内存版队列，避免测试碰 SQLite。
class _FakePlaylistService extends PlaylistService {
  _FakePlaylistService(List<Music> tracks, int index)
    : _tracks = ValueNotifier(List.of(tracks)),
      _index = ValueNotifier(index);

  final ValueNotifier<List<Music>> _tracks;
  final ValueNotifier<int?> _index;
  final ValueNotifier<List<Music>> _history = ValueNotifier([]);
  final ValueNotifier<List<Music>> _favorites = ValueNotifier([]);

  @override
  ValueListenable<List<Music>> get currentPlaylist => _tracks;

  @override
  ValueListenable<int?> get currentIndex => _index;

  @override
  ValueListenable<List<Music>> get playHistory => _history;

  @override
  ValueListenable<List<Music>> get favorites => _favorites;

  @override
  Music? get currentMusic {
    final i = _index.value;
    if (i == null || i < 0 || i >= _tracks.value.length) return null;
    return _tracks.value[i];
  }

  @override
  int get playlistLength => _tracks.value.length;

  @override
  int? get currentIndexSync => _index.value;

  @override
  void setCurrentIndex(int index) {
    if (index >= 0 && index < _tracks.value.length) {
      _index.value = index;
    }
  }

  @override
  int? getNextIndex(PlayMode playMode, {Random? random}) {
    final i = _index.value;
    if (i == null || _tracks.value.isEmpty) return null;
    return (i + 1) % _tracks.value.length;
  }

  @override
  bool isFavorite(Music music) => false;

  @override
  Future<void> addToPlayHistory(Music music) async {
    _history.value = [music, ..._history.value];
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

/// 不落盘的缓存实现。只为绕开 [ApiService] 默认构造里的音乐缓存
/// （它会在测试环境里去找 path_provider）。
class _FakeCacheManager implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 每条曲目的取流结果由测试手动放行，用来精确控制完成顺序。
class _FakeApiService extends ApiService {
  _FakeApiService() : super(musicCache: _FakeCacheManager());

  final Map<String, Completer<({String path, String qualityId})>> pending = {};

  @override
  Future<({String path, String qualityId})> getAudioUrl(
    Music music, {
    String qualityId = '30280',
  }) {
    final completer = Completer<({String path, String qualityId})>();
    pending[music.id] = completer;
    return completer.future;
  }

  @override
  Future<Music> ensureCid(Music music) async => music;

  void complete(String id, String path) {
    final completer = pending.remove(id);
    expect(completer, isNotNull, reason: '没有等待中的取流：$id');
    completer!.complete((path: path, qualityId: '30280'));
  }
}

Music _music(String id) => Music(
  id: id,
  cid: 'cid-$id',
  title: 'track-$id',
  artist: const Artist(name: 'artist'),
  album: 'album',
  coverUrl: '',
  audioUrl: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('后选曲目先取流完成时，慢的旧曲不得在之后落到播放器上', () async {
    final m1 = _music('BV1');
    final m2 = _music('BV2');
    final playlist = _FakePlaylistService([m1, m2], 0);
    final audio = _FakeDualAudioService();
    final api = _FakeApiService();

    final coordinator = PlayerCoordinator(
      audioService: audio,
      audioEffectsService: AudioEffectsService(),
      settingsManager: SettingsManager(),
      playlistService: playlist,
      notificationService: NotificationService(),
      apiService: api,
      roamingService: RoamingService(
        client: BiliClient(),
        playlistService: playlist,
      ),
    );

    // 选中第 1 首：它在等取流。
    final first = coordinator.playAtIndex(0);
    // 还没缓冲完就切到第 2 首。
    final second = coordinator.playAtIndex(1);

    // 第 2 首先完成并开播。
    api.complete('BV2', '/cache/2.m4a');
    await pumpEventQueue();

    // 第 1 首姗姗来迟：必须被丢弃，不能以第 2 首的元数据出声。
    api.complete('BV1', '/cache/1.m4a');
    await pumpEventQueue();

    await first;
    await second;

    expect(audio.played, ['/cache/2.m4a']);
    expect(playlist.currentIndexSync, 1);

    await coordinator.dispose();
  });

  test('新曲还在取流时，旧曲的完成事件不得再把索引推一首', () async {
    final m1 = _music('BV1');
    final m2 = _music('BV2');
    final playlist = _FakePlaylistService([m1, m2], 0);
    final audio = _FakeDualAudioService();
    final api = _FakeApiService();

    final coordinator = PlayerCoordinator(
      audioService: audio,
      audioEffectsService: AudioEffectsService(),
      settingsManager: SettingsManager(),
      playlistService: playlist,
      notificationService: NotificationService(),
      apiService: api,
      roamingService: RoamingService(
        client: BiliClient(),
        playlistService: playlist,
      ),
    );

    // 用户选中第 1 首，它还在取流；此时上一首恰好播完。
    final pendingPlay = coordinator.playAtIndex(0);
    audio.onPlaybackCompleted?.call();

    // 给完成回调里的降级 playNext() 留足 100ms 防抖窗口。
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(playlist.currentIndexSync, 0);
    expect(api.pending.keys, contains('BV1'));
    expect(api.pending.keys, isNot(contains('BV2')));

    api.complete('BV1', '/cache/1.m4a');
    await pumpEventQueue();
    await pendingPlay;

    expect(audio.played, ['/cache/1.m4a']);
    expect(playlist.currentIndexSync, 0);

    await coordinator.dispose();
  });

  test('停止会作废仍在取流的请求', () async {
    final m1 = _music('BV1');
    final playlist = _FakePlaylistService([m1], 0);
    final audio = _FakeDualAudioService();
    final api = _FakeApiService();

    final coordinator = PlayerCoordinator(
      audioService: audio,
      audioEffectsService: AudioEffectsService(),
      settingsManager: SettingsManager(),
      playlistService: playlist,
      notificationService: NotificationService(),
      apiService: api,
      roamingService: RoamingService(
        client: BiliClient(),
        playlistService: playlist,
      ),
    );

    final pendingPlay = coordinator.playAtIndex(0);
    await coordinator.stop();

    api.complete('BV1', '/cache/1.m4a');
    await pumpEventQueue();
    await pendingPlay;

    expect(audio.played, ['<stop>']);

    await coordinator.dispose();
  });
}
