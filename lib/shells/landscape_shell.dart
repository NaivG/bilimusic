import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/components/common/background_blur_widget.dart';
import 'package:bilimusic/shells/landscape/landscape_sidebar.dart';
import 'package:bilimusic/shells/landscape/landscape_bottom_control.dart';
import 'package:bilimusic/shells/landscape/landscape_home_content.dart';
import 'package:bilimusic/shells/landscape/landscape_title_bar.dart';
import 'package:bilimusic/utils/color_infra.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/pages/home_page.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/pages/cookie_page.dart';
import 'package:bilimusic/pages/data_management_page.dart';
import 'package:bilimusic/pages/data_migration_page.dart';

/// 横屏模式外壳 - 基于ParticleMusic风格
/// 布局：标题栏 + 侧边栏 + 主内容区 + 底部播放器栏
class LandscapeShell extends StatefulWidget {
  final ShellPage currentPage;
  final ShellPageManager pageManager;
  final bool isPcMode;
  final VoidCallback onPlayList;

  const LandscapeShell({
    super.key,
    required this.currentPage,
    required this.pageManager,
    required this.isPcMode,
    required this.onPlayList,
  });

  @override
  State<LandscapeShell> createState() => _LandscapeShellState();
}

class _LandscapeShellState extends State<LandscapeShell> {
  @override
  void initState() {
    super.initState();
    sl.playerManager.addStateListener((_) => _onMusicChanged());
    widget.pageManager.addListener(_onPageChanged);
  }

  void _onMusicChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    sl.playerManager.removeStateListener((_) => _onMusicChanged());
    widget.pageManager.removeListener(_onPageChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    updateColors(isDark: isDark);
  }


  /// 主内容渲染
  Widget _buildPageContent(ShellPage page) {
    switch (page) {
      case ShellPage.home:
        return LandscapeHomeContent(
          playlists: sl.playlistManager.userPlaylists,
          selectedPlaylistId: null,
          onPlaylistTap: (id) {
            widget.pageManager.goToPlaylist(playlistId: id);
          },
        );
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
        return PlaylistPage(
          playlistId: playlistId,
          songs: songs,
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
      case ShellPage.login:
        return const ProfilePage(); // TODO: Login page
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
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, child) {
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 背景模糊层
              _buildBackground(),
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
                            color: sidebarColor.withValues(alpha: 0.2),
                            child: _buildPageContent(widget.currentPage),
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
      },
    );
  }

  /// 背景模糊效果
  Widget _buildBackground() {
    final currentMusic = sl.playerManager.currentMusic;
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
        widget.pageManager.goToTab(1);
      },
      onSettingsTap: () {
        widget.pageManager.goToTab(3);
      },
    );
  }

  /// 侧边栏
  Widget _buildSidebar() {
    final selectedLabel = _getSelectedLabel();
    return LandscapeSidebar(
      selectedLabel: selectedLabel,
      playlists: sl.playlistManager.userPlaylists,
      selectedPlaylistId: widget.pageManager.getArgs<String>('selectedPlaylistId'),
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
