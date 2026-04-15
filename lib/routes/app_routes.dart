import 'package:flutter/material.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/pages/login_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/managers/cache_manager.dart';

/// 路由页面过渡策略
enum RouteTransition {
  /// Material 风格滑动过渡（移动端）
  material,
  /// 桌面端过渡（Fade 效果）
  desktop,
}

/// 基于平台选择路由过渡策略
RouteTransition getRouteTransition(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  // 宽屏 >= 1200dp 使用桌面过渡
  if (width >= 1200) {
    return RouteTransition.desktop;
  }
  return RouteTransition.material;
}

/// 创建平台自适应的路由
PageRoute<T> createPageRoute<T>({
  required RouteSettings settings,
  required WidgetBuilder builder,
  RouteTransition? transition,
}) {
  final effectiveTransition = transition ?? RouteTransition.material;

  switch (effectiveTransition) {
    case RouteTransition.material:
      return MaterialPageRoute<T>(settings: settings, builder: builder);
    case RouteTransition.desktop:
      return _DesktopPageRoute<T>(settings: settings, builder: builder);
  }
}

/// 桌面端页面路由（Fade 过渡）
class _DesktopPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  _DesktopPageRoute({required RouteSettings settings, required this.builder})
      : super(settings: settings);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
      BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return builder(context);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class AppRoutes {
  static PageRoute<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    // 在路由切换时清理缓存（可选）
    if (settings.name != '/detail') {
      _clearOldCache();
    }

    // 注意：onGenerateRoute 中无法访问 context 获取 MediaQuery
    // 因此默认使用 Material 过渡，调用方可在导航时使用 platformRoute 指定桌面过渡
    switch (settings.name) {
      case '/detail':
        return MaterialPageRoute(
          settings: RouteSettings(name: '/detail'),
          builder: (_) => const DetailPage(),
        );
      case '/playlist':
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => PlaylistPage(
              playlistId: args['playlistId'] as String?,
              songs: args['songs'] as List<Music>?,
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
          builder: (_) => const SearchPage(),
        );
      case '/search-with-query':
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => SearchPage(
              initialQuery: args['query'] as String?,
            ),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(body: Center(child: Text('无效的搜索参数'))),
        );
      default:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              const Scaffold(body: Center(child: Text('404 页面未找到'))),
        );
    }
  }

  /// 便捷方法：在有 context 的地方创建平台自适应路由
  static PageRoute<T> platformRoute<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? name,
  }) {
    return createPageRoute<T>(
      settings: RouteSettings(name: name),
      builder: builder,
      transition: getRouteTransition(context),
    );
  }

  static void _clearOldCache() {
    // 可以根据需要调整清理策略
    LocalStorage.clearCache();
  }
}
