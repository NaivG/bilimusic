import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/logic/mini_player_auto_hide.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/app/shells/shell_widgets.dart';
import 'package:bilimusic/app/shells/widgets/desktop_window_controls.dart';
import 'package:bilimusic/features/home/home_page.dart';
import 'package:bilimusic/features/player/widgets/mini_player_bar.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 竖屏模式外壳：铺满的页面内容 + 浮在上面的迷你播放器与浮动 Dock。
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
    _miniPlayerHidden.dispose();
    super.dispose();
  }

  /// 是否显示底部导航栏
  bool get _showBottomBar {
    return widget.currentPage == ShellPage.home ||
        widget.currentPage == ShellPage.discover ||
        widget.currentPage == ShellPage.profile ||
        widget.currentPage == ShellPage.settings;
  }

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
    return buildShellPageContent(
      page: entry.page,
      args: entry.args,
      homePage: const HomePage(),
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
    final showMiniPlayer = _showMiniPlayer(alwaysShowMiniPlayer);
    final miniPlayerCanAutoHide = _miniPlayerCanAutoHide(alwaysShowMiniPlayer);
    // 从迷你播放器的定位里扣掉键盘高度，让它保持屏幕上的原位，再由收缩后的 body 底边（键盘上沿）
    // 裁掉，呈现被键盘直接盖住的效果。
    // 你别管路子野不野，你就说有没有解决问题吧.jpg
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 有 Dock 时 Dock 自己吃 safe area；没有 Dock 时迷你条自己让出底部安全区。
    final dockBottom = BmTokens.dockBottom + safeBottom;
    final miniBottom = _showBottomBar
        ? BmTokens.miniPlayerBottom + safeBottom
        : BmTokens.dockBottom + safeBottom;
    // 页面铺到屏幕底，由浮动 chrome 盖在上面；滚动内容按这段高度留白，
    // 这样内容能从 Dock / 迷你条下面滚过去，最后一项仍能滚到它们上方。
    final double chromeInset;
    if (_showBottomBar) {
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
          NotificationListener<ScrollNotification>(
            onNotification: (notification) => _onScrollNotification(
              notification,
              enabled: miniPlayerCanAutoHide,
            ),
            child: _withChromeInset(
              context,
              bottom: chromeInset,
              child: shellPageSwitcher(
                key: widget.pageManager.basePageKey,
                kind: widget.pageManager.lastTransitionKind,
                direction: widget.pageManager.lastTransitionDirection,
                child: _buildPageContent(widget.pageManager.baseEntry),
              ),
            ),
          ),
          // 详情页独立动画层（与底层切换完全解耦）
          buildShellDetailLayer(currentPage: widget.currentPage),
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
          if (_showBottomBar)
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
      ),
    );
  }

  /// 把浮动 chrome 的高度写进页面子树的底部安全区。
  ///
  /// 页面里的列表 / 网格会自动消费 `MediaQuery.padding`，自绘滚动视图则显式
  /// 读取；这样内容可以滚到 Dock / 迷你条下面，最后一项仍能滚到它们上方。
  Widget _withChromeInset(
    BuildContext context, {
    required double bottom,
    required Widget child,
  }) {
    if (bottom <= 0) return child;
    final mediaQuery = MediaQuery.of(context);
    // 键盘弹起时 chrome 被顶到键盘下面，页面不再需要为它让位。
    final inset = mediaQuery.viewInsets.bottom > 0
        ? 0.0
        : bottom + mediaQuery.viewPadding.bottom;
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(bottom: inset),
      ),
      child: child,
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
