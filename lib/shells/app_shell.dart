import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';
import 'package:bilimusic/shells/landscape_shell.dart';
import 'package:bilimusic/shells/portrait_shell.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

/// 统一入口Shell - 根据屏幕方向路由到对应的Shell
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ShellPageManager _pageManager = ShellPageManager.instance;
  final bool _isPcPlatform = PlatformHelper.isDesktop;

  @override
  void initState() {
    super.initState();
    _pageManager.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    _pageManager.removeListener(_onPageChanged);
    super.dispose();
  }

  void _onPageChanged() {
    if (mounted) setState(() {});
  }

  bool _isTabletMode(BuildContext context) {
    switch (sl.settingsManager.tabletMode) {
      case 'on':
        return true;
      case 'off':
        return false;
      case 'auto':
      default:
        return MediaQuery.of(context).size.shortestSide >= 600;
    }
  }

  void _openPlayList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaylistSheet(
        onTrackSelect: (index) {
          sl.playerManager.playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _pageManager.canPop) {
          _pageManager.pop();
        }
      },
      child: ListenableBuilder(
        listenable: _pageManager,
        builder: (context, child) {
          final currentPage = _pageManager.currentPage;

          // 横屏布局优先判断
          if (LandscapeBreakpoints.shouldUseLandscapeLayout(context)) {
            return _buildLandscapeShell(currentPage);
          }

          // 竖屏布局
          return _buildPortraitShell(currentPage);
        },
      ),
    );
  }

  Widget _buildLandscapeShell(ShellPage currentPage) {
    return LandscapeShell(
      currentPage: currentPage,
      pageManager: _pageManager,
      isPcMode: sl.settingsManager.pcMode,
      onPlayList: _openPlayList,
    );
  }

  Widget _buildPortraitShell(ShellPage currentPage) {
    return PortraitShell(
      currentPage: currentPage,
      pageManager: _pageManager,
      isTabletMode: _isTabletMode(context),
      isPcPlatform: _isPcPlatform,
      isPcMode: sl.settingsManager.pcMode,
      onPlayList: _openPlayList,
    );
  }
}
