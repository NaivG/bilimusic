import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/pages/home_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';
import 'package:bilimusic/shells/landscape_shell.dart';
import 'package:bilimusic/shells/portrait_shell.dart';

/// 统一入口Shell - 根据屏幕方向路由到对应的Shell
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  String? _selectedPlaylistId;
  List<Widget> _pages = [];
  final bool _isPcPlatform = PlatformHelper.isDesktop;
  String? _landscapePendingQuery; // 横屏搜索栏的待搜索词

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pages.isEmpty) {
      _pages = [
        const HomePage(),
        const SearchPage(),
        const ProfilePage(),
        const SettingsPage(),
      ];
      if (mounted) setState(() {});
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _setLandscapeSearchQuery(String query) {
    _landscapePendingQuery = query;
  }

  void _onPlaylistTap(String playlistId) {
    setState(() {
      _selectedPlaylistId = playlistId;
    });

    Navigator.pushNamed(
      context,
      '/playlist',
      arguments: {'playlistId': playlistId},
    );
  }

  void _openDetail() {
    if (sl.playerManager.currentMusic == null) return;
    Navigator.pushNamed(context, '/detail');
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

  bool get _isPcMode => sl.settingsManager.pcMode;

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

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 横屏布局优先判断
    if (LandscapeBreakpoints.shouldUseLandscapeLayout(context)) {
      return LandscapeShell(
        selectedIndex: _selectedIndex,
        pages: _pages,
        playlists: sl.playlistManager.userPlaylists,
        allTags: const [],
        selectedPlaylistId: _selectedPlaylistId,
        onNavTap: _onItemTapped,
        onPlaylistTap: _onPlaylistTap,
        onExpand: _openDetail,
        onPlayList: _openPlayList,
        onWindowClose: () => sl.playerManager.stop(),
        onSearchSubmit: _setLandscapeSearchQuery,
        onProfileTap: () => _onItemTapped(2),
        onSettingsTap: () => _onItemTapped(3),
        landscapePendingQuery: _landscapePendingQuery,
      );
    }

    // 竖屏布局
    return PortraitShell(
      selectedIndex: _selectedIndex,
      pages: _pages,
      isTabletMode: _isTabletMode(context),
      isPcPlatform: _isPcPlatform,
      isPcMode: _isPcMode,
      onItemTapped: _onItemTapped,
      onExpand: () {},
      onPlayList: _openPlayList,
    );
  }
}
