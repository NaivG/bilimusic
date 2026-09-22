import 'package:flutter/material.dart';
import 'package:bilimusic/domain/music.dart';

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
  audioBackend,
  audioDsp,
  audioOutput,
  login,
  favImport,
  roamOnboarding,
  lanSync,
}

/// 页面栈中的一帧：页面 + 该帧自己的导航参数。
///
/// 参数随帧入栈/出栈：push 时携带、pop 后自动恢复上一帧自己的参数。
/// 修复旧实现（全局扁平 args map）中「歌单 B 压在歌单 A 上再返回，
/// 页面内容与侧边栏高亮仍停留在 B」的串参问题；多层搜索结果同理。
class ShellPageEntry {
  final ShellPage page;

  /// 本帧页面自己的参数（playlistId / songs / query 等），不可变。
  final Map<String, dynamic> args;

  /// playlist 页专属的导航代数：[ShellPageManager.goToPlaylist] 每次自增
  /// （含同页重复点击），用于让 AnimatedSwitcher 区分不同 push 实例、
  /// 重建页面并触发入场动画；返回上一帧时 key 变回上一帧的代数，
  /// 底层页面随之正确重建。其余页面的 key 用页面名，不依赖该值。
  final int navGen;

  ShellPageEntry(this.page, {Map<String, dynamic>? args, this.navGen = 0})
    : args = args == null ? const {} : Map.unmodifiable(args);
}

class ShellPageManager extends ChangeNotifier {
  ShellPageManager._();

  static final ShellPageManager instance = ShellPageManager._();

  final List<ShellPageEntry> _stack = [ShellPageEntry(ShellPage.home)];

  /// 每次 [goToPlaylist] 自增，写入对应帧的 [ShellPageEntry.navGen]。
  int _playlistNavGen = 0;

  ShellPage get currentPage => _stack.last.page;
  bool get canPop => _stack.length > 1;

  /// 栈中最后一个非 detail 的帧（含它自己的 args），作为 PortraitShell
  /// 底层主内容的目标。当栈顶是 detail 时，详情页作为独立动画层叠在上面，
  /// 底层继续显示 basePage，这样 detail 的进入/离开不会和底层横滑过渡相互打架。
  ShellPageEntry get baseEntry {
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].page != ShellPage.detail) return _stack[i];
    }
    return _stack.first;
  }

  ShellPage get basePage => baseEntry.page;

  /// 底层页面在 AnimatedSwitcher 中使用的 key：
  /// playlist 页用帧的 navGen 区分实例——重复点击同一歌单会重建并触发
  /// 入场动画，从歌单 B 返回歌单 A 也会重建回 A 的内容；
  /// 其余页面沿用页面名（tab 间来回切换不丢元素、不重载）。
  Key get basePageKey => basePage == ShellPage.playlist
      ? ValueKey('playlist-${baseEntry.navGen}')
      : ValueKey(basePage.name);

  /// 侧边栏歌单项的高亮依据：栈顶是 playlist 页时返回其 playlistId
  /// （'favorites' / 'history' / 用户歌单 id 与侧边栏条目一一对应）；
  /// 每日推荐、搜索/主页进来的远程歌单等不在侧边栏中的 id 不匹配任何条目，
  /// 自然不高亮。
  String? get activePlaylistId =>
      currentPage == ShellPage.playlist ? getArgs<String>('playlistId') : null;

  int get selectedTabIndex {
    switch (_stack.last.page) {
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
    _stack.add(ShellPageEntry(page, args: args));
    notifyListeners();
  }

  void pop() {
    if (_stack.length > 1) {
      _stack.removeLast();
      notifyListeners();
    }
  }

  void popUntil(ShellPage page) {
    while (_stack.length > 1 && _stack.last.page != page) {
      _stack.removeLast();
    }
    notifyListeners();
  }

  void replace(ShellPage page, {Map<String, dynamic>? args}) {
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    _stack.add(ShellPageEntry(page, args: args));
    notifyListeners();
  }

  /// 切换顶层 tab：tab 是根页面，直接把栈重置为单一页面。
  /// 旧实现用 replace，会在栈中间留下残留页（如 [home, playlist, home]），
  /// 之后按返回键会「复活」被压住的旧页面。
  void goToTab(int index) {
    final page = switch (index) {
      0 => ShellPage.home,
      1 => ShellPage.search,
      2 => ShellPage.profile,
      3 => ShellPage.settings,
      _ => ShellPage.home,
    };
    _stack
      ..clear()
      ..add(ShellPageEntry(page));
    notifyListeners();
  }

  void goToPlaylist({
    required String playlistId,
    List<Music>? songs,
    String? playlistName,
  }) {
    _playlistNavGen++;
    _stack.add(
      ShellPageEntry(
        ShellPage.playlist,
        args: {
          'playlistId': playlistId,
          'songs': songs,
          'playlistName': playlistName,
        },
        navGen: _playlistNavGen,
      ),
    );
    notifyListeners();
  }

  void goToDetail() {
    push(ShellPage.detail);
  }

  /// 栈顶帧的参数。渲染 basePage 时不要用它（栈顶可能是 detail 等无参页面），
  /// 应使用 [baseEntry].args。
  T? getArgs<T>(String key) => _stack.last.args[key] as T?;
}
