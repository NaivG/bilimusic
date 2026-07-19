import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/services/playlist_service.dart';

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

/// 播放列表命令 - 暴露给 UI 的方法面（替代 UI 直调 sl.playerCoordinator）。
class PlaylistCommands extends Notifier<void> {
  PlaylistService get _ps => ref.read(_playlistServiceProvider);

  @override
  void build() {}

  Future<void> addToPlaylist(Music music) => _ps.addToPlaylist(music);

  Future<void> addAllToPlaylist(List<Music> musics) =>
      _ps.addAllToPlaylist(musics);

  Future<void> removeFromPlaylist(Music music) => _ps.removeFromPlaylist(music);

  Future<void> clearPlaylist() => _ps.clearPlaylist();

  Future<void> moveInPlaylist(int from, int to) => _ps.moveInPlaylist(from, to);

  Future<void> addToFavorites(Music music) => _ps.addToFavorites(music);

  Future<void> removeFromFavorites(Music music) =>
      _ps.removeFromFavorites(music);

  bool isFavorite(Music music) => _ps.isFavorite(music);

  Future<void> toggleFavorite(Music music) => _ps.toggleFavorite(music);

  Future<void> addToPlayHistory(Music music) => _ps.addToPlayHistory(music);
}

final playlistCommandsProvider = NotifierProvider<PlaylistCommands, void>(
  PlaylistCommands.new,
);
