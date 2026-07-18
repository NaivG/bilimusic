import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/services/api_service.dart';
import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/services/notification_service.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/services/search_service.dart';
import 'package:bilimusic/services/pip_service.dart';
import 'package:bilimusic/managers/recommendation_manager.dart';
import 'package:bilimusic/managers/settings_manager.dart';
import 'package:bilimusic/managers/user_manager.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';

/// 应用级服务 / 管理器的依赖容器。
///
/// 这里只放"持有实例"的 Provider；UI 真正消费的状态面放在 `lib/providers/*` 下，
/// 由这些 Provider 提供底层服务。所有依赖关系用 `ref.watch` 声明，编译期即可
/// 推断初始化顺序；测试可通过 `ProviderContainer(overrides: [...])` 替换任意依赖。

// ==================== 基础无依赖服务 ====================

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final pipServiceProvider = Provider<PipService>((ref) {
  return PipService();
});

// ==================== 双播放器服务 ====================

final dualAudioServiceProvider = Provider<DualAudioService>((ref) {
  final svc = DualAudioService();
  svc.initialize();
  ref.onDispose(svc.dispose);
  return svc;
});

// ==================== 持久化播放列表 ====================

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final svc = PlaylistService();
  // 异步初始化 DB；UI 通过 playlist providers 订阅初始化后的数据。
  svc.initialize();
  ref.onDispose(svc.dispose);
  return svc;
});

final playlistManagerProvider = Provider<PlaylistManager>((ref) {
  final mgr = PlaylistManager();
  // 复用上面的 playlistService 实例，保持单一真理源。
  mgr.initialize(service: ref.watch(playlistServiceProvider));
  return mgr;
});

// ==================== 设置 / 用户 / 收藏同步 ====================

final settingsManagerProvider = Provider<SettingsManager>((ref) {
  final mgr = SettingsManager();
  mgr.init();
  return mgr;
});

final userManagerProvider = Provider<UserManager>((ref) {
  final mgr = UserManager();
  mgr.restoreFromPrefs();
  return mgr;
});

final favSyncManagerProvider = Provider<FavSyncManager>((ref) {
  final mgr = FavSyncManager(
    api: ref.watch(apiServiceProvider),
    playlistManager: ref.watch(playlistManagerProvider),
  );
  mgr.initialize();
  return mgr;
});

// ==================== 推荐 ====================

final recommendationManagerProvider = Provider<RecommendationManager>((ref) {
  return RecommendationManager();
});

// ==================== 顶层协调器 ====================

final playerCoordinatorProvider = Provider<PlayerCoordinator>((ref) {
  final pc = PlayerCoordinator(
    audioService: ref.watch(dualAudioServiceProvider),
    settingsManager: ref.watch(settingsManagerProvider),
    playlistService: ref.watch(playlistServiceProvider),
    notificationService: ref.watch(notificationServiceProvider),
    apiService: ref.watch(apiServiceProvider),
  );
  pc.initialize();
  ref.onDispose(pc.dispose);
  return pc;
});