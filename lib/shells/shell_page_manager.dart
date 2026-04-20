import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';

enum ShellPage {
  home,
  search,
  profile,
  settings,
  detail,
  playlist,
  changelog,
  cookie,
  dataManagement,
  dataMigration,
  login,
}

class ShellPageManager extends ChangeNotifier {
  ShellPageManager._();

  static final ShellPageManager instance = ShellPageManager._();

  final List<ShellPage> _pageStack = [ShellPage.home];
  final Map<String, dynamic> _pageArgs = {};

  ShellPage get currentPage => _pageStack.last;
  bool get canPop => _pageStack.length > 1;

  int get selectedTabIndex {
    switch (_pageStack.last) {
      case ShellPage.home:
        return 0;
      case ShellPage.search:
        return 1;
      case ShellPage.profile:
        return 2;
      case ShellPage.settings:
        return 3;
      default:
        return 0;
    }
  }

  void push(ShellPage page, {Map<String, dynamic>? args}) {
    _pageStack.add(page);
    if (args != null) {
      _pageArgs.addAll(args);
    }
    notifyListeners();
  }

  void pop() {
    if (_pageStack.length > 1) {
      _pageStack.removeLast();
      notifyListeners();
    }
  }

  void popUntil(ShellPage page) {
    while (_pageStack.length > 1 && _pageStack.last != page) {
      _pageStack.removeLast();
    }
    notifyListeners();
  }

  void replace(ShellPage page, {Map<String, dynamic>? args}) {
    if (_pageStack.isNotEmpty) {
      _pageStack.removeLast();
    }
    _pageStack.add(page);
    if (args != null) {
      _pageArgs.addAll(args);
    }
    notifyListeners();
  }

  void goToTab(int index) {
    switch (index) {
      case 0:
        replace(ShellPage.home);
        break;
      case 1:
        replace(ShellPage.search);
        break;
      case 2:
        replace(ShellPage.profile);
        break;
      case 3:
        replace(ShellPage.settings);
        break;
    }
  }

  void goToPlaylist({required String playlistId, List<Music>? songs}) {
    push(ShellPage.playlist, args: {'playlistId': playlistId, 'songs': songs});
  }

  void goToDetail() {
    push(ShellPage.detail);
  }

  T? getArgs<T>(String key) => _pageArgs[key] as T?;

  void clearArgs() {
    _pageArgs.clear();
  }
}
