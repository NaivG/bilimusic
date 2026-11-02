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
import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 竖屏模式外壳
/// 主内容 + 迷你播放器 + 底部导航栏
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
    if (
      widget.currentPage == ShellPage.detail ||
      widget.currentPage == ShellPage.roamOnboarding ||
      widget.currentPage == ShellPage.login
    ) {
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
    return _buildPortraitLayout(context, alwaysShowMiniPlayer);
  }

  Widget _buildPortraitLayout(BuildContext context, bool alwaysShowMiniPlayer) {
    final selectedIndex = widget.pageManager.selectedTabIndex;
    final showMiniPlayer = _showMiniPlayer(alwaysShowMiniPlayer);
    final miniPlayerCanAutoHide = _miniPlayerCanAutoHide(alwaysShowMiniPlayer);
    final bottomInset = _showBottomBar
        ? 0.0
        : MediaQuery.paddingOf(context).bottom;

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
            child: shellPageSwitcher(
              key: widget.pageManager.basePageKey,
              child: _buildPageContent(widget.pageManager.baseEntry),
            ),
          ),
          // 详情页独立动画层（与底层切换完全解耦）
          buildShellDetailLayer(currentPage: widget.currentPage),
          // 悬浮迷你播放器
          if (showMiniPlayer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16 + bottomInset,
              child: ValueListenableBuilder<bool>(
                valueListenable: _miniPlayerHidden,
                builder: (context, hidden, _) => _buildMiniPlayer(
                  context,
                  hidden: miniPlayerCanAutoHide && hidden,
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
                    icon: Icon(Icons.explore_outlined),
                    activeIcon: Icon(Icons.explore),
                    label: '发现',
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

  Widget _buildMiniPlayer(BuildContext context, {required bool hidden}) {
    return ExcludeSemantics(
      excluding: hidden,
      child: IgnorePointer(
        ignoring: hidden,
        child: AnimatedSlide(
          offset: hidden ? const Offset(0, 2) : Offset.zero,
          duration: AppTokens.standardDuration,
          curve: AppTokens.standardEasing,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration: AppTokens.standardDuration,
            curve: AppTokens.standardEasing,
            child: Center(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.95,
                child: MiniPlayerBar(
                  onExpand: () => widget.pageManager.push(ShellPage.detail),
                  onPlayList: widget.onPlayList,
                ),
              ),
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
