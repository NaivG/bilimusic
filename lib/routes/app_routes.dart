import 'package:flutter/material.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/pages/login_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/cache_manager.dart';

class AppRoutes {
  static PageRoute<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    // 在路由切换时清理缓存（可选）
    if (settings.name != '/detail') {
      _clearOldCache();
    }

    switch (settings.name) {
      case '/detail':
        if (args != null) {
          // final musicId = args['musicId'] as String;
          final playerManager = args as PlayerManager;

          return MaterialPageRoute(
            settings: RouteSettings(name: '/detail'),
            builder: (_) => DetailPage(
              // musicId: musicId,
              playerManager: playerManager,
            ),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(body: Center(child: Text('无效的音乐ID'))),
        );
      case '/playlist':
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => PlaylistPage(
              playlistId: args['playlistId'] as String?,
              songs: args['songs'] as List<Music>?,
              playerManager: args['playerManager'] as PlayerManager,
            ),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              const Scaffold(body: Center(child: Text('无效的播放列表参数'))),
        );
      case '/login':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => LoginPage(),
        );
      case '/changelog':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ChangelogPage(),
        );
      case '/search':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => SearchPage(playerManager: args as PlayerManager),
        );
      case '/search-with-query':
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => SearchPage(
              playerManager: args['playerManager'] as PlayerManager,
              initialQuery: args['query'] as String?,
            ),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              const Scaffold(body: Center(child: Text('无效的搜索参数'))),
        );
      default:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              const Scaffold(body: Center(child: Text('404 页面未找到'))),
        );
    }
  }

  static void _clearOldCache() {
    // 可以根据需要调整清理策略
    LocalStorage.clearCache();
  }
}
