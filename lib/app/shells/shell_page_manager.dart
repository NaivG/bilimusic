import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';

enum ShellPage {
  home,
  search,
  searchResults,
  profile,
  settings,
  detail,
  playlist,
  changelog,
  cookie,
  dataManagement,
  dataMigration,
  login,
  favImport,
  roamOnboarding,
  lanSync,
}

class ShellPageManager extends ChangeNotifier {
  ShellPageManager._();

  static final ShellPageManager instance = ShellPageManager._();

  final List<ShellPage> _pageStack = [ShellPage.home];
  final Map<String, dynamic> _pageArgs = {};

  /// 每次 [goToPlaylist] 自增，用来让 LandscapeShell 在同一 playlist 上重复点击
  /// 时区分不同的 push 实例，使 KeyedSubtree 重新创建 widget 并触发入场动画。
  int _playlistNavGen = 0;
  int get playlistNavGen => _playlistNavGen;

  ShellPage get currentPage => _pageStack.last;
  bool get canPop => _pageStack.length > 1;

  /// 栈中最后一个非 detail 的页面，作为 PortraitShell 底层主内容的目标。
  /// 当栈顶是 detail 时，详情页作为独立动画层叠在上面，底层继续显示 basePage，
  /// 这样 detail 的进入/离开不会和底层横滑过渡相互打架。
  ShellPage get basePage {
    for (var i = _pageStack.length - 1; i >= 0; i--) {
      if (_pageStack[i] != ShellPage.detail) return _pageStack[i];
    }
    return ShellPage.home;
  }

  int get selectedTabIndex {
    switch (_pageStack.last) {
      case ShellPage.home:
        return 0;
      case ShellPage.search:
      case ShellPage.searchResults:
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

  void goToPlaylist({
    required String playlistId,
    List<Music>? songs,
    String? playlistName,
  }) {
    _playlistNavGen++;
    push(
      ShellPage.playlist,
      args: {
        'playlistId': playlistId,
        'songs': songs,
        'playlistName': playlistName,
      },
    );
  }

  void goToDetail() {
    push(ShellPage.detail);
  }

  T? getArgs<T>(String key) => _pageArgs[key] as T?;

  void clearArgs() {
    _pageArgs.clear();
  }
}
