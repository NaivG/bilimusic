import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/logic/mini_player_auto_hide.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/app/shells/shell_widgets.dart';
import 'package:bilimusic/app/shells/widgets/desktop_window_controls.dart';
import 'package:bilimusic/app/shells/widgets/status_bar_nav_rail.dart';
import 'package:bilimusic/features/home/home_page.dart';
import 'package:bilimusic/features/player/widgets/mini_player_bar.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/chrome/vertical_bar_toolbar.dart';
import 'package:bilimusic/shared/ui/sections/status_bar_safe_area.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/utils/duo_layout.dart';

/// 竖屏模式外壳：铺满的页面内容 + 浮在上面的迷你播放器与浮动 Dock。
///
/// iPhone Duo 有竖栏时（合上），导航和二级页的按钮放进竖栏；展开竖拿时，
/// 页面的顶栏放进状态栏那一行。位置都取系统给的数值（[DuoLayout]）。
class PortraitShell extends ConsumerStatefulWidget {
  final ShellPage currentPage;
  final ShellPageManager pageManager;
  final bool isPcPlatform;
  final VoidCallback onPlayList;

  const PortraitShell({
    super.key,
    required this.currentPage,
    required this.pageManager,
    required this.isPcPlatform,
    required this.onPlayList,
  });

  @override
  ConsumerState<PortraitShell> createState() => _PortraitShellState();
}

class _PortraitShellState extends ConsumerState<PortraitShell> {
  final MiniPlayerAutoHide _autoHide = MiniPlayerAutoHide();
  final ValueNotifier<bool> _miniPlayerHidden = ValueNotifier(false);

  /// 用于判断底层页面是否换了一帧（例如歌单 A → 歌单 B）。
  Key? _basePageKey;

  /// 内容区在「普通布局」和「竖栏布局」之间移动时保留状态。
  ///
  /// iPhone Duo 合上 / 展开的过渡中安全区会短暂变化，两种结构可能来回切；
  /// 没有这个 key，页面会被重建、滚动位置丢失。
  final GlobalKey _contentKey = GlobalKey();

  /// 详情层同理：竖栏布局下它挪到整窗，换结构时不重建播放页。
  final GlobalKey _detailKey = GlobalKey();

  /// 竖栏布局下，二级页导航栏的按钮登记在这里、画在竖栏顶端。
  final VerticalBarToolbarController _barToolbar =
      VerticalBarToolbarController();

  @override
  void initState() {
    super.initState();
    _basePageKey = widget.pageManager.basePageKey;
  }

  @override
  void didUpdateWidget(covariant PortraitShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final basePageKey = widget.pageManager.basePageKey;
    if (oldWidget.currentPage != widget.currentPage ||
        _basePageKey != basePageKey) {
      _autoHide.reset();
      _miniPlayerHidden.value = false;
    }
    _basePageKey = basePageKey;
  }

  @override
  void dispose() {
    _barToolbar.dispose();
    _miniPlayerHidden.dispose();
    super.dispose();
  }

  /// 是否显示底部导航栏
  bool get _showBottomBar => _isTabPage(widget.currentPage);

  static bool _isTabPage(ShellPage page) =>
      page == ShellPage.home ||
      page == ShellPage.discover ||
      page == ShellPage.profile ||
      page == ShellPage.settings;

  /// 是否显示悬浮迷你播放器。
  bool _showMiniPlayer(bool alwaysShowMiniPlayer) {
    if (widget.currentPage == ShellPage.detail ||
        widget.currentPage == ShellPage.roamOnboarding ||
        widget.currentPage == ShellPage.login) {
      return false;
    }
    return _showBottomBar || alwaysShowMiniPlayer;
  }

  /// 其他页面的迷你播放器随滚动方向收起/展开；顶部导航页保持常驻。
  bool _miniPlayerCanAutoHide(bool alwaysShowMiniPlayer) {
    return alwaysShowMiniPlayer &&
        widget.currentPage != ShellPage.detail &&
        !_showBottomBar;
  }

  Widget _buildPageContent(ShellPageEntry entry) {
    final page = buildShellPageContent(
      page: entry.page,
      args: entry.args,
      homePage: const HomePage(),
    );
    // 标签页自己用 StatusBarSafeArea 处理顶部。二级页的导航栏：iPhone Duo
    // 展开竖拿时放进状态栏那一行；有竖栏时按钮放进竖栏。
    if (_isTabPage(entry.page)) return page;
    final hasVerticalBar = DuoLayout.verticalBarOf(context) != null;
    return VerticalBarToolbarScope(
      controller: hasVerticalBar ? _barToolbar : null,
      child: StatusBarToolbarArea(child: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentIndexProvider);
    final alwaysShowMiniPlayer = ref.watch(
      settingsProvider.select((settings) => settings.alwaysShowMiniPlayer),
    );
    final blurEffect = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );
    return _buildPortraitLayout(context, alwaysShowMiniPlayer, blurEffect);
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    bool alwaysShowMiniPlayer,
    bool blurEffect,
  ) {
    final selectedIndex = widget.pageManager.selectedTabIndex;
    // iPhone Duo 合上时，导航放进竖栏，不再画底部 Dock。
    final verticalBar = DuoLayout.verticalBarOf(context);
    final showDock = _showBottomBar && verticalBar == null;
    final showMiniPlayer = _showMiniPlayer(alwaysShowMiniPlayer);
    final miniPlayerCanAutoHide = _miniPlayerCanAutoHide(alwaysShowMiniPlayer);
    // 从迷你播放器的定位里扣掉键盘高度，让它保持屏幕上的原位，再由收缩后的 body 底边（键盘上沿）
    // 裁掉，呈现被键盘直接盖住的效果。
    // 你别管路子野不野，你就说有没有解决问题吧.jpg
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 有 Dock 时 Dock 自己吃 safe area；没有 Dock 时迷你条自己让出底部安全区。
    final dockBottom = BmTokens.dockBottom + safeBottom;
    final miniBottom = showDock
        ? BmTokens.miniPlayerBottom + safeBottom
        : BmTokens.dockBottom + safeBottom;
    // 页面铺到屏幕底，由浮动 chrome 盖在上面；滚动内容按这段高度留白，
    // 这样内容能从 Dock / 迷你条下面滚过去，最后一项仍能滚到它们上方。
    final double chromeInset;
    if (showDock) {
      chromeInset = BmTokens.portraitBottomBudget;
    } else if (showMiniPlayer) {
      chromeInset = BmTokens.miniPlayerOnlyBottomBudget;
    } else {
      chromeInset = 0;
    }

    return Scaffold(
      appBar: widget.isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: (index) => widget.pageManager.goToTab(index),
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          buildShellBackground(context, ref),
          if (verticalBar == null)
            _buildContent(
              chromeInset: chromeInset,
              miniBottom: miniBottom,
              dockBottom: dockBottom,
              keyboardInset: keyboardInset,
              selectedIndex: selectedIndex,
              showDock: showDock,
              showMiniPlayer: showMiniPlayer,
              miniPlayerCanAutoHide: miniPlayerCanAutoHide,
              blurEffect: blurEffect,
            )
          else
            Row(
              children: [
                if (verticalBar.onLeft)
                  _buildVerticalBar(verticalBar, selectedIndex),
                Expanded(
                  child: verticalBar.removePadding(
                    context: context,
                    child: _buildContent(
                      includeDetailLayer: false,
                      chromeInset: chromeInset,
                      miniBottom: miniBottom,
                      dockBottom: dockBottom,
                      keyboardInset: keyboardInset,
                      selectedIndex: selectedIndex,
                      showDock: showDock,
                      showMiniPlayer: showMiniPlayer,
                      miniPlayerCanAutoHide: miniPlayerCanAutoHide,
                      blurEffect: blurEffect,
                    ),
                  ),
                ),
                if (!verticalBar.onLeft)
                  _buildVerticalBar(verticalBar, selectedIndex),
              ],
            ),
          // 有竖栏时详情页（沉浸式）铺满整窗、连竖栏一起盖住，
          // 页面自己的安全区会让开摄像头和状态栏。
          if (verticalBar != null) _buildDetailLayer(),
        ],
      ),
    );
  }

  Widget _buildDetailLayer() {
    return KeyedSubtree(
      key: _detailKey,
      child: StatusBarToolbarArea(
        child: buildShellDetailLayer(currentPage: widget.currentPage),
      ),
    );
  }

  /// 竖栏：从上到下是摄像头和状态栏、当前页面的按钮（二级页的返回键等）、
  /// 标签导航（最下面）。区域取系统给竖栏的位置。
  Widget _buildVerticalBar(VerticalBar bar, int selectedIndex) {
    return SizedBox(
      width: bar.width,
      child: Column(
        children: [
          SizedBox(height: bar.barTop),
          if (!_showBottomBar)
            VerticalBarToolbar(controller: _barToolbar, width: bar.width),
          const Spacer(),
          if (_showBottomBar)
            StatusBarNavRail(
              width: bar.width,
              items: _dockItems,
              selectedIndex: selectedIndex,
              onSelected: (index) => widget.pageManager.goToTab(index),
            ),
          SizedBox(height: bar.barBottom),
        ],
      ),
    );
  }

  /// 页面、详情层、迷你播放器与 Dock。
  Widget _buildContent({
    bool includeDetailLayer = true,
    required double chromeInset,
    required double miniBottom,
    required double dockBottom,
    required double keyboardInset,
    required int selectedIndex,
    required bool showDock,
    required bool showMiniPlayer,
    required bool miniPlayerCanAutoHide,
    required bool blurEffect,
  }) {
    return Stack(
      key: _contentKey,
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) => _onScrollNotification(
            notification,
            enabled: miniPlayerCanAutoHide,
          ),
          // 用内层 context：竖栏布局下，这里的安全区已去掉竖栏一侧。
          child: Builder(
            builder: (context) => shellPageSwitcher(
              key: widget.pageManager.basePageKey,
              kind: widget.pageManager.lastTransitionKind,
              direction: widget.pageManager.lastTransitionDirection,
              // 让位包在页面内层：过渡期旧页保持自己的底距，两页互不干扰。
              child: applyShellChromeInset(
                context,
                bottom: chromeInset,
                child: _buildPageContent(widget.pageManager.baseEntry),
              ),
            ),
          ),
        ),
        // 展开竖拿时状态栏那一块的底色：内容滚到它底下时文字不重叠。
        const StatusBarBacking(),
        // 详情页独立动画层（与底层切换完全解耦）
        if (includeDetailLayer) _buildDetailLayer(),
        // 悬浮迷你播放器（Dock 上方）
        if (showMiniPlayer)
          Positioned(
            left: BmTokens.miniPlayerInset,
            right: BmTokens.miniPlayerInset,
            bottom: miniBottom - keyboardInset,
            child: ValueListenableBuilder<bool>(
              valueListenable: _miniPlayerHidden,
              builder: (context, hidden, _) => _buildMiniPlayer(
                context,
                hidden: miniPlayerCanAutoHide && hidden,
              ),
            ),
          ),
        // 浮动 Dock
        if (showDock)
          Positioned(
            left: BmTokens.dockInset,
            right: BmTokens.dockInset,
            bottom: dockBottom,
            child: BmDock(
              items: _dockItems,
              selectedIndex: selectedIndex,
              onSelected: (index) => widget.pageManager.goToTab(index),
              blur: blurEffect,
            ),
          ),
      ],
    );
  }

  static const List<BmDockItem> _dockItems = <BmDockItem>[
    BmDockItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: '首页',
    ),
    BmDockItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: '发现',
    ),
    BmDockItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: '我的',
    ),
    BmDockItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  Widget _buildMiniPlayer(BuildContext context, {required bool hidden}) {
    return ExcludeSemantics(
      excluding: hidden,
      child: IgnorePointer(
        ignoring: hidden,
        child: AnimatedSlide(
          offset: hidden ? const Offset(0, 2) : Offset.zero,
          duration: BmMotion.medium,
          curve: BmMotion.standard,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration: BmMotion.medium,
            curve: BmMotion.standard,
            child: MiniPlayerBar(
              onExpand: () => widget.pageManager.push(ShellPage.detail),
              onPlayList: widget.onPlayList,
            ),
          ),
        ),
      ),
    );
  }

  bool _onScrollNotification(
    ScrollNotification notification, {
    required bool enabled,
  }) {
    if (!enabled || notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollEndNotification) {
      _autoHide.reset();
      return false;
    }
    if (notification is! ScrollUpdateNotification) return false;

    final delta = notification.scrollDelta;
    if (delta == null || delta == 0) return false;

    final shouldHide = _autoHide.update(
      delta,
      atTop: notification.metrics.extentBefore <= 0,
    );
    if (shouldHide != null && shouldHide != _miniPlayerHidden.value) {
      _miniPlayerHidden.value = shouldHide;
    }
    return false;
  }
}
