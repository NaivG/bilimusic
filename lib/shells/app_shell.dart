import 'package:flutter/material.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/pages/home_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/managers/settings_manager.dart';
import 'package:bilimusic/providers/playlist_manager_provider.dart';
import 'package:bilimusic/providers/player_manager_provider.dart';
import 'package:bilimusic/providers/search_state_provider.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';
import 'package:bilimusic/shells/landscape_shell.dart';
import 'package:bilimusic/shells/portrait_shell.dart';

/// 统一入口Shell - 根据屏幕方向路由到对应的Shell
class AppShell extends StatefulWidget {
  final PlayerManager playerManager;
  final PlaylistManager playlistManager;

  const AppShell({
    super.key,
    required this.playerManager,
    required this.playlistManager,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  String? _selectedPlaylistId;
  late PlayerManager _playerManager;
  late PlaylistManager _playlistManager;
  late SettingsManager _settingsManager;
  List<Widget> _pages = [];
  final bool _isPcPlatform = PlatformHelper.isDesktop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _playerManager = PlayerManagerProvider.of(context);
      _playlistManager = PlaylistManagerProvider.of(context);
      _settingsManager = SettingsManager();
      _settingsManager.init();

      if (_pages.isEmpty) {
        _pages = [
          HomePage(playerManager: _playerManager),
          SearchPage(playerManager: _playerManager),
          ProfilePage(playerManager: _playerManager),
          SettingsPage(),
        ];
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Error initializing AppShell: $e");
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onPlaylistTap(String playlistId) {
    setState(() {
      _selectedPlaylistId = playlistId;
    });

    Navigator.pushNamed(
      context,
      '/playlist',
      arguments: {'playlistId': playlistId, 'playerManager': _playerManager},
    );
  }

  void _openPlayList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaylistSheet(
        playerManager: _playerManager,
        onTrackSelect: (index) {
          _playerManager.playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  bool get _isPcMode => _settingsManager.pcMode;

  bool _isTabletMode(BuildContext context) {
    switch (_settingsManager.tabletMode) {
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
        playlists: _playlistManager.userPlaylists,
        allTags: const [],
        selectedPlaylistId: _selectedPlaylistId,
        onNavTap: _onItemTapped,
        onPlaylistTap: _onPlaylistTap,
        playerManager: _playerManager,
        onExpand: () {},
        onPlayList: _openPlayList,
        onWindowClose: () => _playerManager.stop(),
        onSearch: (query) {
          SearchStateProvider.of(context).setQuery(query);
        },
        onProfileTap: () => _onItemTapped(2),
        onSettingsTap: () => _onItemTapped(3),
      );
    }

    // 竖屏布局
    return PortraitShell(
      selectedIndex: _selectedIndex,
      pages: _pages,
      playerManager: _playerManager,
      isTabletMode: _isTabletMode(context),
      isPcPlatform: _isPcPlatform,
      isPcMode: _isPcMode,
      onItemTapped: _onItemTapped,
      onExpand: () {},
      onPlayList: _openPlayList,
    );
  }
}
