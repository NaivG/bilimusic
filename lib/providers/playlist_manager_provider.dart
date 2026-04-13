import 'package:flutter/material.dart';
import 'package:bilimusic/managers/playlist_manager.dart';

/// PlaylistManager Provider
/// 使用 InheritedWidget 提供 PlaylistManager 实例
class PlaylistManagerProvider extends InheritedWidget {
  final PlaylistManager playlistManager;

  const PlaylistManagerProvider({
    super.key,
    required this.playlistManager,
    required super.child,
  });

  /// 从 BuildContext 获取 PlaylistManager
  static PlaylistManager of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<PlaylistManagerProvider>();
    return provider?.playlistManager ?? PlaylistManager();
  }

  @override
  bool updateShouldNotify(PlaylistManagerProvider oldWidget) {
    return playlistManager != oldWidget.playlistManager;
  }
}
