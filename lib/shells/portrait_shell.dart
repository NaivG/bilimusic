import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/components/mini_player.dart';
import 'package:bilimusic/components/desktop_window_controls.dart';
import 'package:bilimusic/components/common/background_blur_widget.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/pages/home_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/pages/cookie_page.dart';
import 'package:bilimusic/pages/data_management_page.dart';
import 'package:bilimusic/pages/data_migration_page.dart';

/// 竖屏模式外壳 - 包含平板模式和手机模式布局
/// 平板：NavigationRail + 主内容 + 迷你播放器
/// 手机：主内容 + 迷你播放器 + 底部导航栏
class PortraitShell extends StatefulWidget {
  final ShellPage currentPage;
  final ShellPageManager pageManager;
  final bool isTabletMode;
  final bool isPcPlatform;
  final bool isPcMode;
  final VoidCallback onPlayList;

  const PortraitShell({
    super.key,
    required this.currentPage,
    required this.pageManager,
    required this.isTabletMode,
    required this.isPcPlatform,
    required this.isPcMode,
    required this.onPlayList,
  });

  @override
  State<PortraitShell> createState() => _PortraitShellState();
}

class _PortraitShellState extends State<PortraitShell> {
  @override
  void initState() {
    super.initState();
    sl.playlistService.currentIndex.addListener(_onMusicChanged);
    sl.playerManager.addStateListener((_) => _onMusicChanged());
  }

  @override
  void dispose() {
    sl.playlistService.currentIndex.removeListener(_onMusicChanged);
    sl.playerManager.removeStateListener((_) => _onMusicChanged());
    super.dispose();
  }

  void _onMusicChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTabletMode) {
      return _buildTabletLayout(context);
    } else {
      return _buildMobileLayout(context);
    }
  }

  /// 主内容渲染
  Widget _buildPageContent(ShellPage page) {
    switch (page) {
      case ShellPage.home:
        return const HomePage();
      case ShellPage.search:
        return const SearchPage();
      case ShellPage.profile:
        return const ProfilePage();
      case ShellPage.settings:
        return const SettingsPage();
      case ShellPage.detail:
        return const DetailPage();
      case ShellPage.playlist:
        final playlistId = widget.pageManager.getArgs<String>('playlistId');
        final songs = widget.pageManager.getArgs<List<Music>>('songs');
        return PlaylistPage(playlistId: playlistId, songs: songs);
      case ShellPage.changelog:
        return const ChangelogPage();
      case ShellPage.cookie:
        return const CookiePage();
      case ShellPage.dataManagement:
        return const DataManagementPage();
      case ShellPage.dataMigration:
        return const DataMigrationPage();
      case ShellPage.login:
        return const ProfilePage(); // TODO: Login page
    }
  }

  /// 是否显示底部导航栏
  bool get _showBottomBar {
    return widget.currentPage == ShellPage.home ||
        widget.currentPage == ShellPage.search ||
        widget.currentPage == ShellPage.profile ||
        widget.currentPage == ShellPage.settings;
  }

  /// 平板模式布局
  Widget _buildTabletLayout(BuildContext context) {
    final selectedIndex = widget.pageManager.selectedTabIndex;

    return Scaffold(
      appBar: widget.isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: (index) => widget.pageManager.goToTab(index),
                onClose: () => sl.playerManager.stop(),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          Row(
            children: [
              // 侧边导航栏（非PC模式）
              widget.isPcMode
                  ? const SizedBox(width: 0)
                  : SizedBox(
                      width: 80,
                      child: NavigationRail(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (int index) {
                          widget.pageManager.goToTab(index);
                        },
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.home),
                            label: Text('首页'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.search),
                            label: Text('搜索'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.person),
                            label: Text('我的'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings),
                            label: Text('设置'),
                          ),
                        ],
                      ),
                    ),
              // 主内容区域
              Expanded(
                child: Stack(
                  children: [
                    _buildPageContent(widget.currentPage),
                    // 平板模式下的悬浮迷你播放器
                    if (_showBottomBar)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 20,
                        child: Center(
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.8,
                            child: MiniPlayerComponent(
                              onExpand: () =>
                                  widget.pageManager.push(ShellPage.detail),
                              onPlayList: widget.onPlayList,
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
  Widget _buildMobileLayout(BuildContext context) {
    final selectedIndex = widget.pageManager.selectedTabIndex;

    return Scaffold(
      appBar: widget.isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: (index) => widget.pageManager.goToTab(index),
                onClose: () => sl.playerManager.stop(),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          _buildPageContent(widget.currentPage),
          // 悬浮迷你播放器
          if (_showBottomBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.95,
                  child: MiniPlayerComponent(
                    onExpand: () => widget.pageManager.push(ShellPage.detail),
                    onPlayList: widget.onPlayList,
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
                onTap: (index) => widget.pageManager.goToTab(index),
              ),
            )
          : null,
    );
  }

  /// 背景模糊效果
  Widget _buildBackground() {
    final currentMusic = sl.playerManager.currentMusic;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: BackgroundBlurWidget(
        key: ValueKey(currentMusic?.coverUrl),
        coverUrl: currentMusic?.coverUrl,
      ),
    );
  }
}
