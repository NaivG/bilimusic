import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/core/network/bili_client.dart';
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
///
/// [removeFromPlaylist] 的索引语义与真实实现保持一致：删除当前曲目后指针
/// 落到删除位置上的后继（删到队尾环绕回队首）；真实 SQLite 路径由
/// `test/playlist/playlist_service_test.dart` 覆盖。
class _FakePlaylistService extends PlaylistService {
  _FakePlaylistService(List<Music> tracks, int? index)
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
  Future<void> removeFromPlaylist(Music music) async {
    final list = _tracks.value;
    final removeIdx = list.indexWhere((m) => m.sameTrackAs(music));
    if (removeIdx == -1) return;

    final newList = List<Music>.from(list)..removeAt(removeIdx);
    _tracks.value = newList;

    final currentIdx = _index.value;
    if (currentIdx == null) return;
    if (removeIdx == currentIdx) {
      _index.value = newList.isEmpty ? null : removeIdx % newList.length;
    } else if (removeIdx < currentIdx) {
      _index.value = currentIdx - 1;
    }
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

class _ImmediateApiService extends ApiService {
  _ImmediateApiService() : super(musicCache: _FakeCacheManager());

  @override
  Future<({String path, String qualityId})> getAudioUrl(
    Music music, {
    String qualityId = '30280',
  }) async => (path: '/cache/${music.id}.m4a', qualityId: '30280');

  @override
  Future<Music> ensureCid(Music music) async => music;
}

/// 取流结果由测试手动放行，用来制造「删除时旧曲还在取流」的竞争。
class _ControllableApiService extends ApiService {
  _ControllableApiService() : super(musicCache: _FakeCacheManager());

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

PlayerCoordinator _newCoordinator(
  _FakePlaylistService playlist,
  _FakeDualAudioService audio, {
  ApiService? api,
}) {
  return PlayerCoordinator(
    audioService: audio,
    audioEffectsService: AudioEffectsService(),
    settingsManager: SettingsManager(),
    playlistService: playlist,
    notificationService: NotificationService(),
    apiService: api ?? _ImmediateApiService(),
    roamingService: RoamingService(
      client: BiliClient(),
      playlistService: playlist,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('删除正在播放的曲目后接播下一首', () async {
    final m1 = _music('BV1');
    final m2 = _music('BV2');
    final m3 = _music('BV3');
    final playlist = _FakePlaylistService([m1, m2, m3], 0);
    final audio = _FakeDualAudioService();
    final coordinator = _newCoordinator(playlist, audio);

    await coordinator.removeFromPlaylist(m1);

    expect(playlist.currentPlaylist.value.map((m) => m.id).toList(), [
      'BV2',
      'BV3',
    ]);
    expect(playlist.currentIndexSync, 0);
    expect(coordinator.currentMusic?.id, 'BV2');
    expect(audio.played, ['/cache/BV2.m4a']);

    await coordinator.dispose();
  });

  test('删到队尾时按环绕语义接播队首', () async {
    final m1 = _music('BV1');
    final m2 = _music('BV2');
    final playlist = _FakePlaylistService([m1, m2], 1);
    final audio = _FakeDualAudioService();
    final coordinator = _newCoordinator(playlist, audio);

    await coordinator.removeFromPlaylist(m2);

    expect(playlist.currentIndexSync, 0);
    expect(coordinator.currentMusic?.id, 'BV1');
    expect(audio.played, ['/cache/BV1.m4a']);

    await coordinator.dispose();
  });

  test('删除非当前曲目不影响正在播放的音频', () async {
    final m1 = _music('BV1');
    final m2 = _music('BV2');
    final m3 = _music('BV3');
    final playlist = _FakePlaylistService([m1, m2, m3], 0);
    final audio = _FakeDualAudioService();
    final coordinator = _newCoordinator(playlist, audio);

    await coordinator.removeFromPlaylist(m3);

    expect(audio.played, isEmpty);
    expect(playlist.currentIndexSync, 0);
    expect(coordinator.currentMusic?.id, 'BV1');

    await coordinator.dispose();
  });

  test('删掉唯一的当前曲目后停播', () async {
    final m1 = _music('BV1');
    final playlist = _FakePlaylistService([m1], 0);
    final audio = _FakeDualAudioService();
    final coordinator = _newCoordinator(playlist, audio);

    await coordinator.removeFromPlaylist(m1);

    expect(audio.played, ['<stop>']);
    expect(playlist.currentPlaylist.value, isEmpty);
    expect(playlist.currentIndexSync, isNull);
    expect(coordinator.currentMusic, isNull);

    await coordinator.dispose();
  });

  test('删除正在取流的当前曲目：旧请求作废，改播下一首', () async {
    final m1 = _music('BV1');
    final m2 = _music('BV2');
    final playlist = _FakePlaylistService([m1, m2], 0);
    final audio = _FakeDualAudioService();
    final api = _ControllableApiService();
    final coordinator = _newCoordinator(playlist, audio, api: api);

    // 当前曲目还在取流，用户就把它从队列里删了。
    final pendingPlay = coordinator.playAtIndex(0);
    await pumpEventQueue();
    expect(api.pending.keys, contains('BV1'));

    final removal = coordinator.removeFromPlaylist(m1);
    await pumpEventQueue();
    expect(api.pending.keys, contains('BV2'));

    // 下一首先就绪，旧曲的流迟到：不得再落到播放器上。
    api.complete('BV2', '/cache/BV2.m4a');
    await pumpEventQueue();
    api.complete('BV1', '/cache/BV1.m4a');
    await pumpEventQueue();

    await pendingPlay;
    await removal;

    expect(audio.played, ['/cache/BV2.m4a']);
    expect(playlist.currentIndexSync, 0);

    await coordinator.dispose();
  });
}
