import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/providers/settings_provider.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';
import 'package:bilimusic/components/pip/pip_overlay.dart';
import 'package:bilimusic/services/pip_service.dart';
import 'package:bilimusic/shells/landscape_shell.dart';
import 'package:bilimusic/shells/portrait_shell.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

/// 统一入口Shell - 根据屏幕方向路由到对应的Shell
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final ShellPageManager _pageManager = ShellPageManager.instance;
  final PipService _pipService = PipService();
  final bool _isPcPlatform = PlatformHelper.isDesktop;

  @override
  void initState() {
    super.initState();
    _pageManager.addListener(_onPageChanged);
    _pipService.addListener(_onPipChanged);
  }

  @override
  void dispose() {
    _pageManager.removeListener(_onPageChanged);
    _pipService.removeListener(_onPipChanged);
    super.dispose();
  }

  void _onPageChanged() {
    if (mounted) setState(() {});
  }

  void _onPipChanged() {
    if (mounted) setState(() {});
  }

  bool _isTabletMode(BuildContext context) {
    switch (ref.watch(settingsProvider).tabletMode) {
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
          ref.read(playbackCommandsProvider.notifier).playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端 PiP 模式优先渲染
    if (_pipService.isPipMode) {
      return const PipOverlay();
    }

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
      onPlayList: _openPlayList,
    );
  }

  Widget _buildPortraitShell(ShellPage currentPage) {
    return PortraitShell(
      currentPage: currentPage,
      pageManager: _pageManager,
      isTabletMode: _isTabletMode(context),
      isPcPlatform: _isPcPlatform,
      onPlayList: _openPlayList,
    );
  }
}
