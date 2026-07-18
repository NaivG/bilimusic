import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/search/search_overlay.dart';
import 'package:bilimusic/pages/search/search_results_overlay.dart';
import 'package:bilimusic/components/common/background_blur_widget.dart';
import 'package:bilimusic/shells/landscape/landscape_sidebar.dart';
import 'package:bilimusic/shells/landscape/landscape_bottom_control.dart';
import 'package:bilimusic/shells/landscape/landscape_title_bar.dart';
import 'package:bilimusic/pages/home_content.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/providers/search_providers.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/pages/cookie_page.dart';
import 'package:bilimusic/pages/data_management_page.dart';
import 'package:bilimusic/pages/data_migration_page.dart';
import 'package:bilimusic/pages/login_page.dart';
import 'package:bilimusic/pages/fav_import_page.dart';

/// 横屏模式外壳 - 基于ParticleMusic风格
/// 布局：标题栏 + 侧边栏 + 主内容区 + 底部播放器栏
class LandscapeShell extends ConsumerStatefulWidget {
  final ShellPage currentPage;
  final ShellPageManager pageManager;
  final VoidCallback onPlayList;

  const LandscapeShell({
    super.key,
    required this.currentPage,
    required this.pageManager,
    required this.onPlayList,
  });

  @override
  ConsumerState<LandscapeShell> createState() => _LandscapeShellState();
}

class _LandscapeShellState extends ConsumerState<LandscapeShell> {
  @override
  void initState() {
    super.initState();
    widget.pageManager.addListener(_onPageChanged);
  }

  void _onPageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.pageManager.removeListener(_onPageChanged);
    super.dispose();
  }

  /// 主内容渲染
  Widget _buildPageContent(ShellPage page) {
    switch (page) {
      case ShellPage.home:
        return const HomeContent(showAppBar: false);
      case ShellPage.search:
        return const SearchOverlay();
      case ShellPage.searchResults:
        final query = widget.pageManager.getArgs<String>('query') ?? '';
        return SearchResultsOverlay(query: query);
      case ShellPage.profile:
        return const ProfilePage();
      case ShellPage.settings:
        return const SettingsPage();
      case ShellPage.detail:
        return const DetailPage();
      case ShellPage.playlist:
        final playlistId = widget.pageManager.getArgs<String>('playlistId');
        final songs = widget.pageManager.getArgs<List<Music>>('songs');
        final playlistName = widget.pageManager.getArgs<String>('playlistName');
        return PlaylistPage(
          playlistId: playlistId,
          songs: songs,
          playlistName: playlistName,
          onBack: () => widget.pageManager.pop(),
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

  /// 是否显示侧边栏（除详情页外所有页面都显示侧边栏）
  bool get _showSidebar {
    return widget.currentPage != ShellPage.detail;
  }

  /// 是否显示 Shell 的导航 chrome（标题栏 + 底部播放器）
  /// 详情页全屏显示，不需要这些
  bool get _showShellChrome {
    return widget.currentPage != ShellPage.detail;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentIndexProvider);
    final brightness = Theme.of(context).brightness;
    final sidebarSurface = LucentTokens.sidebarSurface(brightness);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景模糊层（依赖当前播放曲目）
          _buildBackground(context),
          // 主内容
          Column(
            children: [
              // 标题栏
              if (_showShellChrome) _buildTitleBar(),
              // 主内容区域
              Expanded(
                child: Row(
                  children: [
                    // 侧边栏
                    if (_showSidebar) _buildSidebar(),
                    // 内容区
                    Expanded(
                      child: Material(
                        color: sidebarSurface.withValues(alpha: 0.2),
                        child: AnimatedSwitcher(
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
                          child: _buildPageContent(widget.currentPage),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 底部播放器
              if (_showShellChrome)
                LandscapeBottomControl(
                  onExpand: () => widget.pageManager.push(ShellPage.detail),
                  onPlayList: widget.onPlayList,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 背景模糊效果
  Widget _buildBackground(BuildContext context) {
    if (sl.settingsManager.fluidBackground == false) {
      final isDark = Theme.of(context).brightness;
      return Container(
        color: isDark == Brightness.dark
            ? LucentTokens.darkSurfaceBase
            : LucentTokens.lightSurfaceBase,
      );
    }
    final currentMusic = sl.playerCoordinator.currentMusic;
    return AnimatedSwitcher(
      switchInCurve: Curves.linearToEaseOut,
      switchOutCurve: Curves.easeInToLinear,
      duration: const Duration(milliseconds: 400),
      child: BackgroundBlurWidget(
        key: ValueKey(currentMusic?.coverUrl),
        coverUrl: currentMusic?.coverUrl,
      ),
    );
  }

  /// 标题栏
  Widget _buildTitleBar() {
    return LandscapeTitleBar(
      onBack: () => widget.pageManager.pop(),
      onSearchSubmit: (query) {
        ref.read(searchStateProvider.notifier).setQuery(query);
        widget.pageManager.goToTab(1);
      },
      onSettingsTap: () {
        widget.pageManager.goToTab(3);
      },
      onProfileTap: () {
        widget.pageManager.goToTab(2);
      },
    );
  }

  /// 侧边栏
  Widget _buildSidebar() {
    final selectedLabel = _getSelectedLabel();
    return LandscapeSidebar(
      selectedLabel: selectedLabel,
      playlists: sl.playlistManager.userPlaylists,
      selectedPlaylistId: widget.pageManager.getArgs<String>(
        'selectedPlaylistId',
      ),
      onNavTap: _onSidebarNavTap,
      onPlaylistTap: (playlistId) {
        widget.pageManager.goToPlaylist(playlistId: playlistId);
      },
      onCreatePlaylist: null,
    );
  }

  String _getSelectedLabel() {
    final index = widget.pageManager.selectedTabIndex;
    switch (index) {
      case 0:
        return 'home';
      case 1:
        return 'search';
      case 2:
        return 'profile';
      case 3:
        return 'settings';
      default:
        return 'home';
    }
  }

  void _onSidebarNavTap(String label) {
    switch (label) {
      case 'home':
        widget.pageManager.goToTab(0);
        break;
      case 'search':
        widget.pageManager.goToTab(1);
        break;
      case 'settings':
        widget.pageManager.goToTab(3);
        break;
    }
  }
}

