import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';

enum ShellContentType { home, search, profile, settings, playlist }

class ShellNavigationState {
  final ShellContentType contentType;
  final String? playlistId;
  final List<Music>? playlistSongs;
  final int selectedTabIndex;

  const ShellNavigationState({
    this.contentType = ShellContentType.home,
    this.playlistId,
    this.playlistSongs,
    this.selectedTabIndex = 0,
  });

  ShellNavigationState copyWith({
    ShellContentType? contentType,
    String? playlistId,
    List<Music>? playlistSongs,
    int? selectedTabIndex,
    bool clearPlaylist = false,
  }) {
    return ShellNavigationState(
      contentType: contentType ?? this.contentType,
      playlistId: clearPlaylist ? null : (playlistId ?? this.playlistId),
      playlistSongs:
          clearPlaylist ? null : (playlistSongs ?? this.playlistSongs),
      selectedTabIndex: selectedTabIndex ?? this.selectedTabIndex,
    );
  }
}

class ShellNavigationNotifier extends Notifier<ShellNavigationState> {
  @override
  ShellNavigationState build() => const ShellNavigationState();

  void goToPlaylist({required String playlistId, List<Music>? songs}) {
    state = ShellNavigationState(
      contentType: ShellContentType.playlist,
      playlistId: playlistId,
      playlistSongs: songs,
    );
  }

  void goToTab(int index) {
    final contentType = switch (index) {
      0 => ShellContentType.home,
      1 => ShellContentType.search,
      2 => ShellContentType.profile,
      3 => ShellContentType.settings,
      _ => ShellContentType.home,
    };
    state = state.copyWith(
      contentType: contentType,
      selectedTabIndex: index,
      clearPlaylist: true,
    );
  }

  void goHome() {
    state = const ShellNavigationState();
  }

  void maybePop(BuildContext context) {
    if (state.contentType == ShellContentType.playlist) {
      goHome();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}

final shellNavigationProvider =
    NotifierProvider<ShellNavigationNotifier, ShellNavigationState>(
  ShellNavigationNotifier.new,
);
