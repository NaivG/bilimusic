import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrics_now/lyrics_now.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/core/network/bili_client.dart';
import 'package:bilimusic/core/network/passport_store.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/core/network/api_service.dart';
import 'package:bilimusic/features/player/logic/audio_focus_service.dart';
import 'package:bilimusic/features/player/logic/audio_effects_service.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/logic/sleep_timer_service.dart';
import 'package:bilimusic/features/lyrics/lyrics_service.dart';
import 'package:bilimusic/features/player/logic/notification_service.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/features/player/pip/pip_service.dart';
import 'package:bilimusic/features/roam/roaming_service.dart';
import 'package:bilimusic/features/lan_sync/services/device_identity.dart';
import 'package:bilimusic/features/lan_sync/services/lan_sync_service.dart';
import 'package:bilimusic/features/lan_sync/services/pairing_service.dart';
import 'package:bilimusic/features/home/logic/recommendation_manager.dart';
import 'package:bilimusic/features/offline/services/offline_cache_service.dart';
import 'package:bilimusic/app/tray_menu.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/features/auth/user_manager.dart';
import 'package:bilimusic/features/fav_sync/fav_sync_manager.dart';

/// 应用级服务 / 管理器的依赖容器。
///
/// 这里只放"持有实例"的 Provider；UI 真正消费的状态面放在 `lib/providers/*` 下，
/// 由这些 Provider 提供底层服务。所有依赖关系用 `ref.watch` 声明，编译期即可
/// 推断初始化顺序；测试可通过 `ProviderContainer(overrides: [...])` 替换任意依赖。

// ==================== 基础无依赖服务 ====================

/// 离线缓存服务。
///
/// 是长生命周期服务，必须在这里创建：ApiService 依赖它做查表/落盘，
/// 设置页与详情页也直接消费它。放在 [apiServiceProvider] 之前声明，
/// 依赖顺序由 `ref.watch` 自动确定。
final offlineCacheServiceProvider = Provider<OfflineCacheService>((ref) {
  final svc = OfflineCacheService();
  svc.initialize();
  ref.onDispose(svc.dispose);
  return svc;
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final offline = ref.watch(offlineCacheServiceProvider);
  return ApiService(
    // 播放链路：先查离线表（命中则断网也能播），未命中再走临时缓存/联网。
    // 这里**不注入落盘钩子**：播放只借用可回收的临时缓存，只有"下载到离线缓存"
    // 才写永久目录（由 OfflineTracksNotifier.download 显式落盘）。
    offlineResolver: (music, qualityId) =>
        offline.resolveLocal(music, qualityId: qualityId),
  );
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

// ==================== 音频效果 ====================

/// 音频效果（DSP af 链）的独立状态与持久化仓库。
///
/// 效果包是嵌套 JSON、配置项多，与扁平设置不同源，单独落盘
/// （键见 [AudioEffectsService.prefsKey]）。
/// 引擎应用链路在 PlayerCoordinator：
/// 调用方 → PlayerCoordinator.setAudioEffects → DualAudioService（两路）。
final audioEffectsServiceProvider = Provider<AudioEffectsService>((ref) {
  final svc = AudioEffectsService();
  // 幂等；PlayerCoordinator.initialize 也会 await 一次，提前触发读盘
  // 只是收窄「UI 先于恢复读到默认值」的窗口。
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

// ==================== 登录凭据 ====================

/// `refresh_token` 的 SharedPreferences 键。
const String _refreshTokenPrefsKey = 'bili_refresh_token_v1';

/// 登录凭据仓库：refresh_token 这类非 Cookie 的登录凭据（SESSDATA 续期要用）。
///
/// Cookie 由 `NetworkConfig.cookieJar` 负责（main.dart 注入落盘钩子）；
/// refresh_token 是 passport 登录成功时随响应体下发的，单独走这里。
/// TUI 只共享 Cookie 登录态，refresh_token 目前只有 App 侧消费。
final passportStoreProvider = Provider<PassportStore>((ref) {
  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();
  return PassportStore(
    loader: () async => (await prefs()).getString(_refreshTokenPrefsKey),
    saver: (json) async =>
        (await prefs()).setString(_refreshTokenPrefsKey, json),
  );
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
    playlistService: ref.watch(playlistServiceProvider),
  );
  mgr.initialize();
  return mgr;
});

// ==================== 推荐 ====================

final recommendationManagerProvider = Provider<RecommendationManager>((ref) {
  return RecommendationManager();
});

// ==================== 漫游 ====================

final roamingServiceProvider = Provider<RoamingService>((ref) {
  return RoamingService(
    client: BiliClient(),
    playlistService: ref.watch(playlistServiceProvider),
  );
});

// ==================== 顶层协调器 ====================

final playerCoordinatorProvider = Provider<PlayerCoordinator>((ref) {
  final pc = PlayerCoordinator(
    audioService: ref.watch(dualAudioServiceProvider),
    audioEffectsService: ref.watch(audioEffectsServiceProvider),
    settingsManager: ref.watch(settingsManagerProvider),
    playlistService: ref.watch(playlistServiceProvider),
    notificationService: ref.watch(notificationServiceProvider),
    apiService: ref.watch(apiServiceProvider),
    roamingService: ref.watch(roamingServiceProvider),
  );
  pc.initialize();
  ref.onDispose(pc.dispose);
  return pc;
});

// ==================== 音频焦点 ====================

/// 音频焦点补偿：系统媒体会话由 audio_service 独占之后，来电 / 拔耳机等打断行为
/// 由 audio_session 在这里补齐（语义见服务注释）。main.dart 在启动期读取，
/// 保证任何播放开始前 configure 与监听都已就位。
final audioFocusServiceProvider = Provider<AudioFocusService>((ref) {
  final svc = AudioFocusService(
    coordinator: ref.watch(playerCoordinatorProvider),
  );
  ref.onDispose(svc.dispose);
  svc.initialize();
  return svc;
});

// ==================== 定时关闭 ====================

final sleepTimerServiceProvider = Provider<SleepTimerService>((ref) {
  final svc = SleepTimerService(
    coordinator: ref.watch(playerCoordinatorProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

// ==================== 歌词 ====================

final lyricsFinderProvider = Provider<LyricFinder>((ref) {
  final http = PackageHttpClient();
  final finder = LyricFinder(
    http: http,
    providers: [
      LrclibProvider(http),
      KgProvider(http),
      QmProvider(http),
      NeProvider(http),
    ],
    searchCacheTtl: const Duration(hours: 1),
    matcher: const SongMatcher(),
  );
  ref.onDispose(finder.close);
  return finder;
});

/// 歌词缓存管理器。
///
/// 包一层 provider 让测试可以 override 成内存实现。
final lyricsCacheManagerProvider = Provider<CacheManager>((ref) {
  return lyricsCacheManager;
});

final lyricsServiceProvider = Provider<LyricsService>((ref) {
  final svc = LyricsService(
    cache: ref.watch(lyricsCacheManagerProvider),
    finder: ref.watch(lyricsFinderProvider),
  );
  svc.bind(ref.watch(playerCoordinatorProvider));
  ref.onDispose(svc.dispose);
  return svc;
});

// ==================== 局域网同步 ====================

final deviceIdentityProvider = Provider<DeviceIdentity>((ref) {
  final id = DeviceIdentity();
  id.load();
  ref.onDispose(() {});
  return id;
});

final pairingServiceProvider = Provider<PairingService>((ref) {
  final svc = PairingService();
  svc.load();
  return svc;
});

// ==================== 桌面托盘 ====================

/// 托盘右键菜单：曲目信息 / 播放控制 / 收藏 / 播放模式 / 页面入口 / 退出。
///
/// 由 main.dart 在托盘图标建起来之后读取并挂到托盘上（托盘基础设施见
/// `desktop_tray.dart`）：没有托盘时创建它只是白白挂一串播放器监听。
final trayMenuProvider = Provider<TrayMenu>((ref) {
  final menu = TrayMenu(
    coordinator: ref.watch(playerCoordinatorProvider),
    playlistService: ref.watch(playlistServiceProvider),
  );
  ref.onDispose(menu.dispose);
  return menu;
});

final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final svc = LanSyncService(
    identity: ref.watch(deviceIdentityProvider),
    pairing: ref.watch(pairingServiceProvider),
    settings: ref.watch(settingsManagerProvider),
    coordinator: ref.watch(playerCoordinatorProvider),
  );
  svc.start();
  ref.onDispose(svc.stop);
  return svc;
});
