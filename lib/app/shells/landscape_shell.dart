import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/landscape/landscape_bottom_control.dart';
import 'package:bilimusic/app/shells/landscape/landscape_content_stage.dart';
import 'package:bilimusic/app/shells/landscape/landscape_library_drawer.dart';
import 'package:bilimusic/app/shells/landscape/landscape_queue_panel.dart';
import 'package:bilimusic/app/shells/landscape/landscape_rail.dart';
import 'package:bilimusic/app/shells/landscape/landscape_title_bar.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/app/shells/shell_widgets.dart';
import 'package:bilimusic/features/home/home_content.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_suggest_panel.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 横屏外壳：76 图标轨 + 58 标题栏 + 内容区 Stack + 90 播放底栏。
///
/// 三块 chrome（轨 / 标题栏 / 底栏）各自是安全区；资料库抽屉只从内容区
/// 左缘滑出，队列面板只从内容区右缘滑出，都不压 chrome。
class LandscapeShell extends ConsumerStatefulWidget {
  final ShellPage currentPage;
  final ShellPageManager pageManager;

  const LandscapeShell({
    super.key,
    required this.currentPage,
    required this.pageManager,
  });

  @override
  ConsumerState<LandscapeShell> createState() => _LandscapeShellState();
}

class _LandscapeShellState extends ConsumerState<LandscapeShell> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchFocused = false;

  /// 资料库抽屉 / 播放队列面板的本地开关，两者互斥。
  bool _libraryOpen = false;
  bool _queueOpen = false;

  static const double _searchPanelMaxWidth = 360;

  /// 同一份回调用于注册 / 反注册 [HardwareKeyboard]。
  late final bool Function(KeyEvent) _keyHandler = _handleKeyEvent;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    HardwareKeyboard.instance.addHandler(_keyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyHandler);
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
      _libraryOpen = false;
      _queueOpen = false;
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!_libraryOpen && !_queueOpen) return false;
    _closeDrawers();
    return true;
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

  /// 是否显示 Shell 的导航 chrome（轨 / 标题栏 / 底栏）；详情页全窗显示。
  bool get _showShellChrome {
    return widget.currentPage != ShellPage.detail;
  }

  /// 底栏实际高度；`LandscapeBottomControl` 自己按窗口宽度取 90 / 96 / 88。
  /// 搜索遮罩据此停在底栏上沿。
  double _playbarHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= LandscapeBreakpoints.desktopMin) return 90;
    if (width >= LandscapeBreakpoints.largeTabletMin) return 96;
    return 88;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final railWidth = LandscapeBreakpoints.railWidth(context);
          final titleBarHeight = LandscapeTitleBar.heightOf(context);
          final playbarHeight = _playbarHeight(context);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 背景模糊层（依赖当前播放曲目）
              buildShellBackground(context, ref),
              // 轨 + workspace（标题栏 / 内容 / 底栏）
              Row(
                children: [
                  if (_showShellChrome)
                    LandscapeRail(
                      selected: _railSelection,
                      settingsSelected:
                          widget.pageManager.currentPage ==
                              ShellPage.settings &&
                          !_libraryOpen,
                      onSelected: _onRailSelected,
                      onSettings: () {
                        _searchFocusNode.unfocus();
                        widget.pageManager.goToTab(3);
                      },
                      onProfile: () {
                        _searchFocusNode.unfocus();
                        widget.pageManager.goToTab(2);
                      },
                      onSync: _openLanSync,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (_showShellChrome) _buildTitleBar(),
                        Expanded(child: _buildContentStage()),
                        if (_showShellChrome)
                          LandscapeBottomControl(
                            onExpand: () =>
                                widget.pageManager.push(ShellPage.detail),
                            onPlayList: _toggleQueue,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              // 标题栏搜索框驱动的联想面板
              if (_showShellChrome && _searchFocused)
                ..._buildSearchSuggestLayer(
                  constraints.maxHeight,
                  railWidth,
                  titleBarHeight,
                  playbarHeight,
                ),
              // 详情页独立动画层（全窗，与底层切换完全解耦）
              buildShellDetailLayer(currentPage: widget.currentPage),
            ],
          );
        },
      ),
    );
  }

  /// 内容区舞台：页面切换在最底，遮罩 / 资料库抽屉 / 播放队列由
  /// [LandscapeContentStage] 叠放，并裁在内容区之内。
  Widget _buildContentStage() {
    return LandscapeContentStage(
      libraryOpen: _libraryOpen,
      queueOpen: _queueOpen,
      onCloseDrawers: _closeDrawers,
      page: shellPageSwitcher(
        key: widget.pageManager.basePageKey,
        kind: widget.pageManager.lastTransitionKind,
        direction: widget.pageManager.lastTransitionDirection,
        child: buildLandscapeShellPageContent(
          page: widget.pageManager.basePage,
          args: widget.pageManager.baseEntry.args,
          homePage: const HomeContent(showAppBar: false, wide: true),
        ),
      ),
      libraryDrawer: LandscapeLibraryDrawer(
        selectedPlaylistId: widget.pageManager.activePlaylistId,
        onClose: _closeDrawers,
        onOpenPlaylist: _openPlaylist,
        onManageSync: _openLanSync,
      ),
      queuePanel: LandscapeQueuePanel(onClose: _closeDrawers),
    );
  }

  /// 标题栏搜索的联想层：内容区一层可点击遮罩 + 面板。
  ///
  /// [titleBarHeight] 是含状态栏 / 刘海的标题栏总高，面板从它下沿展开。
  /// 面板用 [TextFieldTapRegion] 标记为「输入框的一部分」，否则点联想词会被
  /// TextField 的 TapRegion 当成外部点击先失焦，列表在抬手前就消失了。
  List<Widget> _buildSearchSuggestLayer(
    double bodyHeight,
    double railWidth,
    double titleBarHeight,
    double playbarHeight,
  ) {
    final size = MediaQuery.sizeOf(context);
    final panelLeft = railWidth + BmTokens.searchFieldLeft;
    final panelWidth = (size.width - panelLeft - BmTokens.s5)
        .clamp(240.0, _searchPanelMaxWidth)
        .toDouble();
    final panelHeight =
        (bodyHeight - titleBarHeight - playbarHeight - BmTokens.s5)
            .clamp(140.0, 420.0)
            .toDouble();

    return [
      Positioned(
        left: railWidth,
        top: titleBarHeight,
        right: 0,
        bottom: playbarHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _searchFocusNode.unfocus,
          child: ColoredBox(color: context.bmColors.stateHover),
        ),
      ),
      Positioned(
        top: titleBarHeight + BmTokens.s2,
        left: panelLeft,
        child: TextFieldTapRegion(
          child: BmMenuSurface(
            maxWidth: panelWidth,
            padding: EdgeInsets.zero,
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

  Widget _buildTitleBar() {
    return LandscapeTitleBar(
      pageTitle: _pageTitle,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      onSearchChanged: (value) {
        ref.read(searchSuggestProvider.notifier).update(value);
      },
      onSearchSubmit: _submitSearch,
      onBack: widget.pageManager.pop,
    );
  }

  /// 图标轨的高亮项。
  LandscapeRailDestination? get _railSelection {
    if (!_showShellChrome) return null;
    if (_libraryOpen) return LandscapeRailDestination.library;
    switch (widget.pageManager.currentPage) {
      case ShellPage.home:
        return LandscapeRailDestination.home;
      case ShellPage.discover:
        return LandscapeRailDestination.discover;
      case ShellPage.offline:
        return LandscapeRailDestination.offline;
      case ShellPage.playlist:
        return switch (widget.pageManager.activePlaylistId) {
          'favorites' => LandscapeRailDestination.favorites,
          'history' => LandscapeRailDestination.recent,
          _ => null,
        };
      default:
        return null;
    }
  }

  void _onRailSelected(LandscapeRailDestination destination) {
    if (destination == LandscapeRailDestination.library) {
      _toggleLibrary();
      return;
    }
    _searchFocusNode.unfocus();
    _closeDrawers();
    switch (destination) {
      case LandscapeRailDestination.home:
        widget.pageManager.goToTab(0);
        break;
      case LandscapeRailDestination.discover:
        widget.pageManager.goToTab(1);
        break;
      case LandscapeRailDestination.recent:
        widget.pageManager.goToPlaylist(
          playlistId: 'history',
          playlistName: '最近播放',
        );
        break;
      case LandscapeRailDestination.offline:
        if (widget.pageManager.currentPage != ShellPage.offline) {
          widget.pageManager.push(ShellPage.offline);
        }
        break;
      case LandscapeRailDestination.favorites:
        widget.pageManager.goToPlaylist(
          playlistId: 'favorites',
          playlistName: '我喜欢的音乐',
        );
        break;
      case LandscapeRailDestination.library:
        break;
    }
  }

  void _openPlaylist(String playlistId, String playlistName) {
    _searchFocusNode.unfocus();
    _closeDrawers();
    widget.pageManager.goToPlaylist(
      playlistId: playlistId,
      playlistName: playlistName,
    );
  }

  void _openLanSync() {
    _searchFocusNode.unfocus();
    _closeDrawers();
    widget.pageManager.push(ShellPage.lanSync);
  }

  void _toggleLibrary() {
    _searchFocusNode.unfocus();
    setState(() {
      _libraryOpen = !_libraryOpen;
      if (_libraryOpen) _queueOpen = false;
    });
  }

  void _toggleQueue() {
    _searchFocusNode.unfocus();
    setState(() {
      _queueOpen = !_queueOpen;
      if (_queueOpen) _libraryOpen = false;
    });
  }

  void _closeDrawers() {
    if (!_libraryOpen && !_queueOpen) return;
    setState(() {
      _libraryOpen = false;
      _queueOpen = false;
    });
  }

  /// 面包屑末段：当前页面名。
  String get _pageTitle {
    final entry = widget.pageManager.baseEntry;
    return switch (entry.page) {
      ShellPage.home => '首页',
      ShellPage.discover => '发现',
      ShellPage.searchEntry => '搜索',
      ShellPage.searchResults => '搜索结果',
      ShellPage.profile => '我的',
      ShellPage.settings => '设置',
      ShellPage.offline => '离线缓存',
      ShellPage.detail => '播放详情',
      ShellPage.playlist => _playlistTitle(entry),
      ShellPage.changelog => '更新日志',
      ShellPage.cookie => 'Cookie 管理',
      ShellPage.dataManagement => '数据管理',
      ShellPage.dataMigration => '数据迁移',
      ShellPage.audioBackend => '音频后端',
      ShellPage.audioDsp => '音频 DSP',
      ShellPage.audioOutput => '音频输出',
      ShellPage.login => '登录',
      ShellPage.favImport => '收藏导入',
      ShellPage.following => '关注',
      ShellPage.artist => 'UP 主',
      ShellPage.roamOnboarding => '漫游',
      ShellPage.lanSync => '局域网同步',
      ShellPage.tasteProfile => '品味画像',
    };
  }

  String _playlistTitle(ShellPageEntry entry) {
    final name = (entry.args['playlistName'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    return switch (entry.args['playlistId']) {
      'favorites' => '我喜欢的音乐',
      'history' => '最近播放',
      'recommended' => '每日推荐',
      _ => '歌单',
    };
  }
}
