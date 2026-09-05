import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/domain/playlist_tag.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';

/// 单一播放列表数据源（provider 内缓存服务实例）。
final _playlistServiceProvider = playlistServiceProvider;

class _CurrentPlaylistWatcher extends Notifier<List<Music>> {
  @override
  List<Music> build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.currentPlaylist.addListener(_onChanged);
    ref.onDispose(() => ps.currentPlaylist.removeListener(_onChanged));
    return ps.currentPlaylist.value;
  }

  void _onChanged() =>
      state = ref.read(_playlistServiceProvider).currentPlaylist.value;
}

final currentPlaylistProvider =
    NotifierProvider<_CurrentPlaylistWatcher, List<Music>>(
      _CurrentPlaylistWatcher.new,
    );

class _CurrentIndexWatcher extends Notifier<int?> {
  @override
  int? build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.currentIndex.addListener(_onChanged);
    ref.onDispose(() => ps.currentIndex.removeListener(_onChanged));
    return ps.currentIndex.value;
  }

  void _onChanged() =>
      state = ref.read(_playlistServiceProvider).currentIndex.value;
}

final currentIndexProvider = NotifierProvider<_CurrentIndexWatcher, int?>(
  _CurrentIndexWatcher.new,
);

final currentMusicProvider = Provider<Music?>((ref) {
  final playlist = ref.watch(currentPlaylistProvider);
  final index = ref.watch(currentIndexProvider);
  if (index == null || index < 0 || index >= playlist.length) return null;
  return playlist[index];
});

class _PlayHistoryWatcher extends Notifier<List<Music>> {
  @override
  List<Music> build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.playHistory.addListener(_onChanged);
    ref.onDispose(() => ps.playHistory.removeListener(_onChanged));
    return ps.playHistory.value;
  }

  void _onChanged() =>
      state = ref.read(_playlistServiceProvider).playHistory.value;
}

final playHistoryProvider = NotifierProvider<_PlayHistoryWatcher, List<Music>>(
  _PlayHistoryWatcher.new,
);

class _FavoritesWatcher extends Notifier<List<Music>> {
  @override
  List<Music> build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.favorites.addListener(_onChanged);
    ref.onDispose(() => ps.favorites.removeListener(_onChanged));
    return ps.favorites.value;
  }

  void _onChanged() =>
      state = ref.read(_playlistServiceProvider).favorites.value;
}

final favoritesProvider = NotifierProvider<_FavoritesWatcher, List<Music>>(
  _FavoritesWatcher.new,
);

class _UserPlaylistsWatcher extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.userPlaylists.addListener(_onChanged);
    ref.onDispose(() => ps.userPlaylists.removeListener(_onChanged));
    return ps.userPlaylists.value;
  }

  void _onChanged() =>
      state = ref.read(_playlistServiceProvider).userPlaylists.value;
}

final userPlaylistsProvider =
    NotifierProvider<_UserPlaylistsWatcher, List<Playlist>>(
      _UserPlaylistsWatcher.new,
    );

class _AllTagsWatcher extends Notifier<List<PlaylistTag>> {
  @override
  List<PlaylistTag> build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.allTags.addListener(_onChanged);
    ref.onDispose(() => ps.allTags.removeListener(_onChanged));
    return ps.allTags.value;
  }

  void _onChanged() => state = ref.read(_playlistServiceProvider).allTags.value;
}

final allTagsProvider = NotifierProvider<_AllTagsWatcher, List<PlaylistTag>>(
  _AllTagsWatcher.new,
);

class _CurrentPlaylistDetailWatcher extends Notifier<Playlist?> {
  @override
  Playlist? build() {
    final ps = ref.read(_playlistServiceProvider);
    ps.currentPlaylistDetail.addListener(_onChanged);
    ref.onDispose(() => ps.currentPlaylistDetail.removeListener(_onChanged));
    return ps.currentPlaylistDetail.value;
  }

  void _onChanged() =>
      state = ref.read(_playlistServiceProvider).currentPlaylistDetail.value;
}

final currentPlaylistDetailProvider =
    NotifierProvider<_CurrentPlaylistDetailWatcher, Playlist?>(
      _CurrentPlaylistDetailWatcher.new,
    );

final isFavoriteProvider = Provider.family<bool, Music>((ref, music) {
  final favorites = ref.watch(favoritesProvider);
  return favorites.any((m) => m.id == music.id && m.cid == music.cid);
});

/// 播放列表命令 - 收藏/队列等纯数据操作的单一 UI 门面（直连 PlaylistService）。
///
/// 播放控制（playMusic/pause/…）与清空队列（需停播放器）走 `playbackCommandsProvider`；
/// 通知栏的收藏态由 PlayerCoordinator 监听 favorites 变化刷新，本门面无需回调。
class PlaylistCommands extends Notifier<void> {
  PlaylistService get _ps => ref.read(_playlistServiceProvider);

  @override
  void build() {}

  // ---- 当前播放队列（纯数据操作，通知由 Coordinator 监听 currentPlaylist 刷新） ----

  Future<void> addToPlaylist(Music music) => _ps.addToPlaylist(music);

  Future<void> addAllToPlaylist(List<Music> musics) =>
      _ps.addAllToPlaylist(musics);

  Future<void> removeFromPlaylist(Music music) => _ps.removeFromPlaylist(music);

  Future<void> moveInPlaylist(int from, int to) => _ps.moveInPlaylist(from, to);

  // ---- 收藏 ----

  bool isFavorite(Music music) => _ps.isFavorite(music);

  Future<bool> toggleFavorite(Music music) => _ps.toggleFavorite(music);

  Future<void> addToFavorites(Music music) => _ps.addToFavorites(music);

  Future<void> removeFromFavorites(Music music) =>
      _ps.removeFromFavorites(music);

  // ---- 用户歌单 ----

  Future<void> deletePlaylist(String playlistId) =>
      _ps.deletePlaylist(playlistId);
}

final playlistCommandsProvider = NotifierProvider<PlaylistCommands, void>(
  PlaylistCommands.new,
);
