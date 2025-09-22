import 'package:flutter/material.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/login_page.dart'; // 添加登录页面导入
import 'package:bilimusic/pages/changelog_page.dart'; // 添加 Changelog 页面导入
import 'package:bilimusic/models/music.dart';
// 使用绝对路径导入所有依赖
import 'package:bilimusic/components/player_manager.dart';
import 'package:bilimusic/utils/cache_manager.dart'; // 导入缓存管理器
import 'package:bilimusic/components/playlist_manager.dart'; // 导入播放列表管理器

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
            )
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(
            body: Center(
              child: Text('无效的音乐ID'),
            ),
          ),
        );
      case '/playlist':
        if (args is Map<String, dynamic>) {
          // 检查是否有播放列表ID
          if (args.containsKey('playlistId') && args.containsKey('playlistManager')) {
            // 用户自定义播放列表
            final playlistId = args['playlistId'] as String;
            final playlistName = args['playlistName'] as String;
            final playerManager = args['playerManager'] as PlayerManager;
            final playlistManager = args['playlistManager'] as PlaylistManager;
            
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PlaylistPage(
                playlistId: playlistId,
                playlistName: playlistName,
                playerManager: playerManager,
                playlistManager: playlistManager,
              ),
            );
          } else if (args.containsKey('songs')) {
            // 特殊播放列表（如播放历史、我的收藏等）
            final songs = args['songs'] as List<Music>;
            final playlistName = args['playlistName'] as String;
            final playerManager = args['playerManager'] as PlayerManager;
            
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PlaylistPage(
                songs: songs,
                playlistName: playlistName,
                playerManager: playerManager,
              ),
            );
          }
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(
            body: Center(
              child: Text('无效的播放列表参数'),
            ),
          ),
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
      default:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(
            body: Center(
              child: Text('404 页面未找到'),
            ),
          ),
        );
    }
  }
  
  static void _clearOldCache() {
    // 可以根据需要调整清理策略
    LocalStorage.clearCache();
  }
}