import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/components/mini_player_bar.dart';
import 'package:bilimusic/components/desktop_window_controls.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/shells/shell_widgets.dart';
import 'package:bilimusic/pages/home_page.dart';

/// 竖屏模式外壳 - 包含平板模式和手机模式布局
/// 平板：NavigationRail + 主内容 + 迷你播放器
/// 手机：主内容 + 迷你播放器 + 底部导航栏
class PortraitShell extends ConsumerWidget {
  final ShellPage currentPage;
  final ShellPageManager pageManager;
  final bool isTabletMode;
  final bool isPcPlatform;
  final VoidCallback onPlayList;

  const PortraitShell({
    super.key,
    required this.currentPage,
    required this.pageManager,
    required this.isTabletMode,
    required this.isPcPlatform,
    required this.onPlayList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentIndexProvider);
    if (isTabletMode) {
      return _buildTabletLayout(context, ref);
    } else {
      return _buildMobileLayout(context, ref);
    }
  }

  /// 是否显示底部导航栏
  bool get _showBottomBar {
    return currentPage == ShellPage.home ||
        currentPage == ShellPage.search ||
        currentPage == ShellPage.profile ||
        currentPage == ShellPage.settings;
  }

  ShellPage get _basePage => pageManager.basePage;

  Widget _buildPageContent(ShellPage page) {
    return buildShellPageContent(
      page: page,
      pageManager: pageManager,
      homePage: const HomePage(),
    );
  }

  /// 平板模式布局
  Widget _buildTabletLayout(BuildContext context, WidgetRef ref) {
    final selectedIndex = pageManager.selectedTabIndex;

    return Scaffold(
      appBar: isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: (index) => pageManager.goToTab(index),
                onClose: () =>
                    ref.read(playbackCommandsProvider.notifier).stop(),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          buildShellBackground(context, ref),
          Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    shellPageSwitcher(
                      key: ValueKey(_basePage),
                      child: _buildPageContent(_basePage),
                    ),
                    // 详情页独立动画层（与底层切换完全解耦）
                    buildShellDetailLayer(currentPage: currentPage),
                    if (_showBottomBar)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 20,
                        child: Center(
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.8,
                            child: MiniPlayerBar(
                              onExpand: () =>
                                  pageManager.push(ShellPage.detail),
                              onPlayList: onPlayList,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 手机模式布局
  Widget _buildMobileLayout(BuildContext context, WidgetRef ref) {
    final selectedIndex = pageManager.selectedTabIndex;

    return Scaffold(
      appBar: isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: (index) => pageManager.goToTab(index),
                onClose: () =>
                    ref.read(playbackCommandsProvider.notifier).stop(),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          buildShellBackground(context, ref),
          shellPageSwitcher(
            key: ValueKey(_basePage),
            child: _buildPageContent(_basePage),
          ),
          // 详情页独立动画层（与底层切换完全解耦）
          buildShellDetailLayer(currentPage: currentPage),
          // 悬浮迷你播放器
          if (_showBottomBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.95,
                  child: MiniPlayerBar(
                    onExpand: () => pageManager.push(ShellPage.detail),
                    onPlayList: onPlayList,
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _showBottomBar
          ? Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                elevation: 0,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home),
                    label: '首页',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.search_outlined),
                    activeIcon: Icon(Icons.search),
                    label: '搜索',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outlined),
                    activeIcon: Icon(Icons.person),
                    label: '我的',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    activeIcon: Icon(Icons.settings),
                    label: '设置',
                  ),
                ],
                currentIndex: selectedIndex,
                onTap: (index) => pageManager.goToTab(index),
              ),
            )
          : null,
    );
  }
}
