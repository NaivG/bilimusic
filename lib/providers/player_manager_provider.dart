import 'package:flutter/material.dart';
import 'package:bilimusic/managers/player_manager.dart';

/// 提供播放器管理器的InheritedWidget
class PlayerManagerProvider extends InheritedWidget {
  final PlayerManager playerManager;

  const PlayerManagerProvider({
    super.key,
    required this.playerManager,
    required super.child,
  });

  static PlayerManager of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<PlayerManagerProvider>();
    if (provider == null) {
      throw Exception('No PlayerManager found in the widget tree');
    }
    return provider.playerManager;
  }

  @override
  bool updateShouldNotify(covariant PlayerManagerProvider oldWidget) {
    return playerManager != oldWidget.playerManager;
  }
}
