import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';

class _CurrentPlaylistWatcher extends Notifier<List<Music>> {
  @override
  List<Music> build() {
    final ps = sl.playlistService;
    ps.currentPlaylist.addListener(_onChanged);
    ref.onDispose(() => ps.currentPlaylist.removeListener(_onChanged));
    return ps.currentPlaylist.value;
  }

  void _onChanged() =>
      state = sl.playlistService.currentPlaylist.value;
}

final currentPlaylistProvider =
    NotifierProvider<_CurrentPlaylistWatcher, List<Music>>(
  _CurrentPlaylistWatcher.new,
);

class _CurrentIndexWatcher extends Notifier<int?> {
  @override
  int? build() {
    final ps = sl.playlistService;
    ps.currentIndex.addListener(_onChanged);
    ref.onDispose(() => ps.currentIndex.removeListener(_onChanged));
    return ps.currentIndex.value;
  }

  void _onChanged() =>
      state = sl.playlistService.currentIndex.value;
}

final currentIndexProvider =
    NotifierProvider<_CurrentIndexWatcher, int?>(
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
    final ps = sl.playlistService;
    ps.playHistory.addListener(_onChanged);
    ref.onDispose(() => ps.playHistory.removeListener(_onChanged));
    return ps.playHistory.value;
  }

  void _onChanged() =>
      state = sl.playlistService.playHistory.value;
}

final playHistoryProvider =
    NotifierProvider<_PlayHistoryWatcher, List<Music>>(
  _PlayHistoryWatcher.new,
);

class _FavoritesWatcher extends Notifier<List<Music>> {
  @override
  List<Music> build() {
    final ps = sl.playlistService;
    ps.favorites.addListener(_onChanged);
    ref.onDispose(() => ps.favorites.removeListener(_onChanged));
    return ps.favorites.value;
  }

  void _onChanged() =>
      state = sl.playlistService.favorites.value;
}

final favoritesProvider =
    NotifierProvider<_FavoritesWatcher, List<Music>>(
  _FavoritesWatcher.new,
);

class _UserPlaylistsWatcher extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() {
    final ps = sl.playlistService;
    ps.userPlaylists.addListener(_onChanged);
    ref.onDispose(() => ps.userPlaylists.removeListener(_onChanged));
    return ps.userPlaylists.value;
  }

  void _onChanged() =>
      state = sl.playlistService.userPlaylists.value;
}

final userPlaylistsProvider =
    NotifierProvider<_UserPlaylistsWatcher, List<Playlist>>(
  _UserPlaylistsWatcher.new,
);

class _AllTagsWatcher extends Notifier<List<PlaylistTag>> {
  @override
  List<PlaylistTag> build() {
    final ps = sl.playlistService;
    ps.allTags.addListener(_onChanged);
    ref.onDispose(() => ps.allTags.removeListener(_onChanged));
    return ps.allTags.value;
  }

  void _onChanged() =>
      state = sl.playlistService.allTags.value;
}

final allTagsProvider =
    NotifierProvider<_AllTagsWatcher, List<PlaylistTag>>(
  _AllTagsWatcher.new,
);

class _CurrentPlaylistDetailWatcher extends Notifier<Playlist?> {
  @override
  Playlist? build() {
    final ps = sl.playlistService;
    ps.currentPlaylistDetail.addListener(_onChanged);
    ref.onDispose(() => ps.currentPlaylistDetail.removeListener(_onChanged));
    return ps.currentPlaylistDetail.value;
  }

  void _onChanged() =>
      state = sl.playlistService.currentPlaylistDetail.value;
}

final currentPlaylistDetailProvider =
    NotifierProvider<_CurrentPlaylistDetailWatcher, Playlist?>(
  _CurrentPlaylistDetailWatcher.new,
);

final isFavoriteProvider = Provider.family<bool, Music>((ref, music) {
  final favorites = ref.watch(favoritesProvider);
  return favorites.any((m) => m.id == music.id && m.cid == music.cid);
});
