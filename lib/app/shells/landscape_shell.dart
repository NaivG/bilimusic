import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_suggest_panel.dart';
import 'package:bilimusic/app/shells/landscape/landscape_sidebar.dart';
import 'package:bilimusic/app/shells/landscape/landscape_bottom_control.dart';
import 'package:bilimusic/app/shells/landscape/landscape_title_bar.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/app/shells/shell_widgets.dart';
import 'package:bilimusic/features/home/home_content.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchFocused = false;

  /// 联想面板贴住内容区左缘（与标题栏搜索容器左对齐）。
  static const double _searchPanelLeft = 220;
  static const double _searchPanelMaxWidth = 360;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LandscapeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 详情页会收起标题栏，输入框随之消失；别把焦点和面板留在看不见的地方。
    if (widget.currentPage == ShellPage.detail &&
        oldWidget.currentPage != ShellPage.detail) {
      _searchFocusNode.unfocus();
    }
  }

  void _onSearchFocusChanged() {
    final focused = _searchFocusNode.hasFocus;
    if (!mounted || focused == _searchFocused) return;
    setState(() => _searchFocused = focused);
    if (focused) {
      ref.read(searchSuggestProvider.notifier).update(_searchController.text);
    }
  }

  void _submitSearch(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;

    if (_searchController.text != query) {
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    _searchFocusNode.unfocus();
    ref.read(searchSuggestProvider.notifier).remember(query);
    ref.read(searchResultsProvider.notifier).search(query);
    widget.pageManager.push(ShellPage.searchResults, args: {'query': query});
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
    final sidebarSurface = context.appPalette.sidebarSurface;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 背景模糊层（依赖当前播放曲目）
              buildShellBackground(context, ref),
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
                        if (_showSidebar) _buildSidebar(ref),
                        // 内容区
                        Expanded(
                          child: Material(
                            color: sidebarSurface.withValues(alpha: 0.2),
                            child: shellPageSwitcher(
                              key: widget.pageManager.basePageKey,
                              child: buildShellPageContent(
                                page: widget.pageManager.basePage,
                                args: widget.pageManager.baseEntry.args,
                                homePage: const HomeContent(showAppBar: false),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 标题栏搜索框驱动的联想面板
              if (_showShellChrome && _searchFocused)
                ..._buildSearchSuggestLayer(constraints.maxHeight),
              // 详情页独立动画层（与底层切换完全解耦）
              buildShellDetailLayer(currentPage: widget.currentPage),
            ],
          );
        },
      ),
      // 底部播放条必须放在 Scaffold 的底槽（bottomNavigationBar）里，不能塞进
      // 上面 body 的 Column。
      // 放进底槽后 Scaffold 同样会为它预留 body 高度。
      bottomNavigationBar: _showShellChrome
          ? LandscapeBottomControl(
              onExpand: () => widget.pageManager.push(ShellPage.detail),
              onPlayList: widget.onPlayList,
            )
          : null,
    );
  }

  /// 标题栏底下的搜索联想层：一层可点击的遮罩 + 面板。
  ///
  /// 面板用 [TextFieldTapRegion] 标记为「输入框的一部分」，否则点联想词会被
  /// TextField 的 TapRegion 当成外部点击先失焦，列表在抬手前就消失了。
  List<Widget> _buildSearchSuggestLayer(double bodyHeight) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth = (size.width - _searchPanelLeft - 20)
        .clamp(240.0, _searchPanelMaxWidth)
        .toDouble();
    final panelHeight = (bodyHeight - LandscapeTitleBar.height - 20)
        .clamp(140.0, 420.0)
        .toDouble();

    return [
      Positioned.fill(
        top: LandscapeTitleBar.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _searchFocusNode.unfocus,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      Positioned(
        top: LandscapeTitleBar.height + 8,
        left: _searchPanelLeft,
        child: TextFieldTapRegion(
          child: Material(
            elevation: 12,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelHeight),
                child: SearchSuggestPanel(onSelected: _submitSearch),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// 标题栏
  Widget _buildTitleBar() {
    return LandscapeTitleBar(
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      onSearchChanged: (value) {
        ref.read(searchSuggestProvider.notifier).update(value);
      },
      onSearchSubmit: _submitSearch,
      onBack: () => widget.pageManager.pop(),
      onSettingsTap: () {
        widget.pageManager.goToTab(3);
      },
      onProfileTap: () {
        widget.pageManager.goToTab(2);
      },
    );
  }

  /// 侧边栏
  Widget _buildSidebar(WidgetRef ref) {
    return LandscapeSidebar(
      selectedLabel: _getSelectedLabel(),
      playlists: ref.watch(userPlaylistsProvider),
      // 歌单页时按 playlistId 高亮对应侧边栏项（我喜欢的音乐/最近播放/创建的歌单）；
      // 每日推荐、远程歌单等 id 不在侧边栏中，自然不高亮。
      selectedPlaylistId: widget.pageManager.activePlaylistId,
      onNavTap: _onSidebarNavTap,
      onPlaylistTap: (playlistId) {
        widget.pageManager.goToPlaylist(playlistId: playlistId);
      },
      onCreatePlaylist: null,
    );
  }

  /// 当前应高亮的顶层导航项（首页/发现/我的/设置）。
  /// 在歌单页时返回 null——此时侧边栏的视觉焦点由
  /// [ShellPageManager.activePlaylistId] 交给对应歌单项，避免
  /// 「歌单项和发现同时高亮」或「在歌单页却仍高亮发现」的视觉残留。
  String? _getSelectedLabel() {
    if (widget.pageManager.currentPage == ShellPage.playlist) {
      return null;
    }
    final index = widget.pageManager.selectedTabIndex;
    switch (index) {
      case 0:
        return 'home';
      case 1:
        return 'discover';
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
      case 'discover':
        widget.pageManager.goToTab(1);
        break;
      case 'settings':
        widget.pageManager.goToTab(3);
        break;
    }
  }
}
