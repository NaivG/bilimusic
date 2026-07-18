import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/settings_provider.dart';
import 'package:bilimusic/components/mini_player_bar.dart';
import 'package:bilimusic/components/desktop_window_controls.dart';
import 'package:bilimusic/components/common/background_blur_widget.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/pages/home_page.dart';
import 'package:bilimusic/pages/search/search_overlay.dart';
import 'package:bilimusic/pages/search/search_results_overlay.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/pages/cookie_page.dart';
import 'package:bilimusic/pages/data_management_page.dart';
import 'package:bilimusic/pages/data_migration_page.dart';
import 'package:bilimusic/pages/login_page.dart';
import 'package:bilimusic/pages/fav_import_page.dart';

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

  /// 主内容渲染
  Widget _buildPageContent(ShellPage page) {
    switch (page) {
      case ShellPage.home:
        return const HomePage();
      case ShellPage.search:
        return const SearchOverlay();
      case ShellPage.searchResults:
        final query = pageManager.getArgs<String>('query') ?? '';
        return SearchResultsOverlay(query: query);
      case ShellPage.profile:
        return const ProfilePage();
      case ShellPage.settings:
        return const SettingsPage();
      case ShellPage.detail:
        return const DetailPage();
      case ShellPage.playlist:
        final playlistId = pageManager.getArgs<String>('playlistId');
        final songs = pageManager.getArgs<List<Music>>('songs');
        final playlistName = pageManager.getArgs<String>('playlistName');
        return PlaylistPage(
          playlistId: playlistId,
          songs: songs,
          playlistName: playlistName,
        );
      case ShellPage.changelog:
        return const ChangelogPage();
      case ShellPage.cookie:
        return const CookiePage();
      case ShellPage.dataManagement:
        return const DataManagementPage();
      case ShellPage.dataMigration:
        return const DataMigrationPage();
      case ShellPage.favImport:
        return const FavImportPage();
      case ShellPage.login:
        return LoginPage();
    }
  }

  /// 是否显示底部导航栏
  bool get _showBottomBar {
    return currentPage == ShellPage.home ||
        currentPage == ShellPage.search ||
        currentPage == ShellPage.profile ||
        currentPage == ShellPage.settings;
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
                onClose: () => ref.read(playbackCommandsProvider.notifier).stop(),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(context, ref),
          Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0.03, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          ),
                        );
                      },
                      child: _buildPageContent(currentPage),
                    ),
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
                onClose: () => ref.read(playbackCommandsProvider.notifier).stop(),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(context, ref),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0.03, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              );
            },
            child: _buildPageContent(currentPage),
          ),
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

  /// 背景模糊效果
  Widget _buildBackground(BuildContext context, WidgetRef ref) {
    if (ref.watch(settingsProvider).fluidBackground == false) {
      final isDark = Theme.of(context).brightness;
      return Container(
        color: isDark == Brightness.dark
            ? LucentTokens.darkSurfaceBase
            : LucentTokens.lightSurfaceBase,
      );
    }
    final currentMusic = ref.watch(currentMusicProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: BackgroundBlurWidget(
        key: ValueKey(currentMusic?.coverUrl),
        coverUrl: currentMusic?.coverUrl,
      ),
    );
  }
}
