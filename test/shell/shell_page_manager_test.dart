import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/shared/motion/bm_page_switcher.dart';

/// `ShellPageManager` 记录的动作与方向必须和栈变化一致。
void main() {
  final manager = ShellPageManager.instance;

  setUp(() {
    // 单例在同一个测试文件里跨用例复用，先复位到单页 tab 栈。
    manager.goToTab(0);
  });

  test('复位后最近动作为 tab/+1', () {
    expect(manager.lastTransitionKind, BmPageTransitionKind.tab);
    expect(manager.lastTransitionDirection, 1);
    expect(manager.currentPage, ShellPage.home);
  });

  test('push 记 push/+1，pop 记 pop/-1', () {
    manager.push(ShellPage.discover);
    expect(manager.lastTransitionKind, BmPageTransitionKind.push);
    expect(manager.lastTransitionDirection, 1);
    expect(manager.currentPage, ShellPage.discover);

    manager.pop();
    expect(manager.lastTransitionKind, BmPageTransitionKind.pop);
    expect(manager.lastTransitionDirection, -1);
    expect(manager.currentPage, ShellPage.home);
  });

  test('空栈 pop 不改变栈，也不覆盖最近动作', () {
    manager.pop();
    expect(manager.currentPage, ShellPage.home);
    expect(manager.lastTransitionKind, BmPageTransitionKind.tab);
    expect(manager.lastTransitionDirection, 1);
  });

  test('goToTab 按下标差给方向，同一个 tab 仍记 +1', () {
    manager.goToTab(3);
    expect(manager.lastTransitionKind, BmPageTransitionKind.tab);
    expect(manager.lastTransitionDirection, 1);
    expect(manager.currentPage, ShellPage.settings);

    manager.goToTab(0);
    expect(manager.lastTransitionDirection, -1);
    expect(manager.currentPage, ShellPage.home);

    manager.goToTab(0);
    expect(manager.lastTransitionDirection, 1);
    expect(manager.currentPage, ShellPage.home);
  });

  test('goToPlaylist 记 push/+1，basePageKey 随 navGen 变化', () {
    final before = manager.basePageKey;
    manager.goToPlaylist(playlistId: 'favorites');
    expect(manager.lastTransitionKind, BmPageTransitionKind.push);
    expect(manager.lastTransitionDirection, 1);
    expect(manager.basePage, ShellPage.playlist);
    expect(manager.basePageKey, isNot(before));

    final firstKey = manager.basePageKey;
    manager.goToPlaylist(playlistId: 'favorites');
    expect(manager.basePageKey, isNot(firstKey));
  });

  test('replace 记 replace/0', () {
    manager.replace(ShellPage.discover);
    expect(manager.lastTransitionKind, BmPageTransitionKind.replace);
    expect(manager.lastTransitionDirection, 0);
    expect(manager.currentPage, ShellPage.discover);
  });

  test('popUntil 有出栈记 pop/-1，无出栈不覆盖', () {
    manager.push(ShellPage.discover);
    manager.push(ShellPage.settings);

    manager.popUntil(ShellPage.home);
    expect(manager.currentPage, ShellPage.home);
    expect(manager.lastTransitionKind, BmPageTransitionKind.pop);
    expect(manager.lastTransitionDirection, -1);

    // 已经在目标页，再调一次不应覆盖「最近动作」。
    manager.goToTab(1);
    manager.popUntil(ShellPage.discover);
    expect(manager.lastTransitionKind, BmPageTransitionKind.tab);
    expect(manager.lastTransitionDirection, 1);
  });

  test('goToDetail 记 push/+1，baseEntry 仍是底层页', () {
    manager.push(ShellPage.offline);
    manager.goToDetail();
    expect(manager.currentPage, ShellPage.detail);
    expect(manager.basePage, ShellPage.offline);
    expect(manager.lastTransitionKind, BmPageTransitionKind.push);
    expect(manager.lastTransitionDirection, 1);
  });
}
