import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';

enum ShellContentType { home, search, profile, settings, playlist }

class ShellNavigationNotifier extends ChangeNotifier {
  ShellNavigationNotifier._();

  static final ShellNavigationNotifier instance = ShellNavigationNotifier._();

  ShellContentType _contentType = ShellContentType.home;
  String? _playlistId;
  List<Music>? _playlistSongs;
  int _selectedTabIndex = 0;
  NavigatorState? _navigator;

  ShellContentType get contentType => _contentType;
  String? get playlistId => _playlistId;
  List<Music>? get playlistSongs => _playlistSongs;
  int get selectedTabIndex => _selectedTabIndex;

  void setNavigator(NavigatorState? navigator) {
    _navigator = navigator;
  }

  void maybePop(BuildContext context) {
    if (_contentType == ShellContentType.playlist) {
      goHome();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<T?> showAppDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? barrierColor,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
    );
  }

  Future<T?> showAppBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      isScrollControlled: isScrollControlled,
    );
  }

  void goToPlaylist({required String playlistId, List<Music>? songs}) {
    _contentType = ShellContentType.playlist;
    _playlistId = playlistId;
    _playlistSongs = songs;
    notifyListeners();
  }

  void goToTab(int index) {
    _selectedTabIndex = index;
    switch (index) {
      case 0:
        _contentType = ShellContentType.home;
        break;
      case 1:
        _contentType = ShellContentType.search;
        break;
      case 2:
        _contentType = ShellContentType.profile;
        break;
      case 3:
        _contentType = ShellContentType.settings;
        break;
    }
    notifyListeners();
  }

  void goHome() {
    _contentType = ShellContentType.home;
    _playlistId = null;
    _playlistSongs = null;
    notifyListeners();
  }
}
