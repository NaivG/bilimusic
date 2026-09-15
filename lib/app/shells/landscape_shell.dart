import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/app/shells/landscape/landscape_sidebar.dart';
import 'package:bilimusic/app/shells/landscape/landscape_bottom_control.dart';
import 'package:bilimusic/app/shells/landscape/landscape_title_bar.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/app/shells/shell_widgets.dart';
import 'package:bilimusic/features/home/home_content.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';

/// 横屏模式外壳 - 基于ParticleMusic风格
/// 布局：标题栏 + 侧边栏 + 主内容区 + 底部播放器栏
class LandscapeShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentIndexProvider);
    final sidebarSurface = context.appPalette.sidebarSurface;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景模糊层（依赖当前播放曲目）
          buildShellBackground(context, ref),
          // 主内容
          Column(
            children: [
              // 标题栏
              if (_showShellChrome) _buildTitleBar(ref),
              // 主内容区域
              Expanded(
                child: Row(
                  children: [
                    // 侧边栏
                    if (_showSidebar) _buildSidebar(ref),
                    // 内容区
                    Expanded(
                      child: Material(
                        color: sidebarSurface.withValues(alpha: 0.2),
                        child: shellPageSwitcher(
                          key: ValueKey(
                            pageManager.basePage == ShellPage.playlist
                                ? 'playlist-${pageManager.playlistNavGen}'
                                : pageManager.basePage.name,
                          ),
                          child: buildShellPageContent(
                            page: pageManager.basePage,
                            pageManager: pageManager,
                            homePage: const HomeContent(showAppBar: false),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 底部播放器
              if (_showShellChrome)
                LandscapeBottomControl(
                  onExpand: () => pageManager.push(ShellPage.detail),
                  onPlayList: onPlayList,
                ),
            ],
          ),
          // 详情页独立动画层（与底层切换完全解耦）
          buildShellDetailLayer(currentPage: currentPage),
        ],
      ),
    );
  }

  /// 是否显示侧边栏（除详情页外所有页面都显示侧边栏）
  bool get _showSidebar {
    return currentPage != ShellPage.detail;
  }

  /// 是否显示 Shell 的导航 chrome（标题栏 + 底部播放器）
  /// 详情页全屏显示，不需要这些
  bool get _showShellChrome {
    return currentPage != ShellPage.detail;
  }

  /// 标题栏
  Widget _buildTitleBar(WidgetRef ref) {
    return LandscapeTitleBar(
      onBack: () => pageManager.pop(),
      onSearchSubmit: (query) {
        ref.read(searchStateProvider.notifier).setQuery(query);
        pageManager.goToTab(1);
      },
      onSettingsTap: () {
        pageManager.goToTab(3);
      },
      onProfileTap: () {
        pageManager.goToTab(2);
      },
    );
  }

  /// 侧边栏
  Widget _buildSidebar(WidgetRef ref) {
    final selectedLabel = _getSelectedLabel();
    return LandscapeSidebar(
      selectedLabel: selectedLabel,
      playlists: ref.watch(userPlaylistsProvider),
      selectedPlaylistId: pageManager.getArgs<String>('selectedPlaylistId'),
      onNavTap: _onSidebarNavTap,
      onPlaylistTap: (playlistId) {
        pageManager.goToPlaylist(playlistId: playlistId);
      },
      onCreatePlaylist: null,
    );
  }

  /// 当前应高亮的顶层导航项。
  /// 在歌单页时返回 null —— `ShellPageManager.selectedTabIndex` 对
  /// `ShellPage.playlist` 退化到 home 索引，所以这里要根据 currentPage
  /// 直接判断，避免出现"在歌单页却仍高亮发现"的视觉残留。
  String? _getSelectedLabel() {
    if (pageManager.currentPage == ShellPage.playlist) {
      return null;
    }
    final index = pageManager.selectedTabIndex;
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
        pageManager.goToTab(0);
        break;
      case 'search':
        pageManager.goToTab(1);
        break;
      case 'settings':
        pageManager.goToTab(3);
        break;
    }
  }
}
