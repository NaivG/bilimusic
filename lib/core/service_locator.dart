import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/managers/settings_manager.dart';
import 'package:bilimusic/managers/recommendation_manager.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/services/notification_service.dart';
import 'package:bilimusic/services/api_service.dart';
import 'package:bilimusic/managers/user_manager.dart';

/// 统一服务定位器
/// 集中管理所有核心管理器和服务的初始化与访问
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator instance = ServiceLocator._();

  bool _isInitialized = false;

  // 核心管理器（延迟初始化）
  PlayerManager? _playerManager;
  PlaylistManager? _playlistManager;
  SettingsManager? _settingsManager;
  RecommendationManager? _recommendationManager;
  UserManager? _userManager;
  FavSyncManager? _favSyncManager;

  // 核心服务
  DualAudioService? _dualAudioService;
  NotificationService? _notificationService;
  ApiService? _apiService;
  PlayerCoordinator? _playerCoordinator;

  // ==================== 便捷访问 ====================

  /// 播放器管理器
  PlayerManager get playerManager => _playerManager!;

  /// 播放列表管理器
  PlaylistManager get playlistManager => _playlistManager!;

  /// 设置管理器
  SettingsManager get settingsManager => _settingsManager!;

  /// 推荐管理器（延迟初始化）
  RecommendationManager get recommendationManager =>
      _recommendationManager ??= RecommendationManager();

  /// 用户管理器
  UserManager get userManager => _userManager!;

  /// 收藏夹同步管理器
  FavSyncManager get favSyncManager => _favSyncManager!;

  /// 双音频服务
  DualAudioService get dualAudioService => _dualAudioService!;

  /// 通知服务
  NotificationService get notificationService => _notificationService!;

  /// API 服务
  ApiService get apiService => _apiService!;

  /// 播放器协调器
  PlayerCoordinator get playerCoordinator => _playerCoordinator!;

  // ==================== 初始化 ====================

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化所有管理器和服务
  /// 应在 main() 中调用一次
  Future<void> init() async {
    if (_isInitialized) return;

    // 创建基础服务
    // Init DualAudioService
    _dualAudioService = DualAudioService();
    _dualAudioService!.initialize();

    _notificationService = NotificationService();
    _apiService = ApiService();

    // 初始化 SettingsManager（最先初始化，其他组件可能依赖它）
    _settingsManager = SettingsManager();
    await _settingsManager!.init();

    // 初始化 UserManager（从持久化缓存恢复）
    _userManager = UserManager();
    await _userManager!.restoreFromPrefs();

    // 共享同一个 PlaylistService 给 PlayerCoordinator 与 PlaylistManager
    final playlistService = PlaylistService();
    await playlistService.initialize();

    // 创建 PlayerCoordinator
    _playerCoordinator = PlayerCoordinator(
      audioService: _dualAudioService!,
      settingsManager: _settingsManager!,
      playlistService: playlistService,
      notificationService: _notificationService!,
      apiService: _apiService!,
    );
    await _playerCoordinator!.initialize();

    // 初始化 PlayerManager
    _playerManager = StreamingPlayerManager.initialize(_playerCoordinator!);

    // 初始化 PlaylistManager 复用同一 service 实例
    _playlistManager = PlaylistManager();
    await _playlistManager!.initialize(service: playlistService);

    // 初始化 FavSyncManager
    _favSyncManager = FavSyncManager(
      api: _apiService!,
      playlistManager: _playlistManager!,
    );
    await _favSyncManager!.initialize();

    _isInitialized = true;
  }

  /// 重置所有实例（主要用于测试）
  void reset() {
    _playerManager = null;
    _playlistManager = null;
    _settingsManager = null;
    _recommendationManager = null;
    _userManager = null;
    _favSyncManager = null;
    _dualAudioService = null;
    _notificationService = null;
    _apiService = null;
    _playerCoordinator = null;
    _isInitialized = false;
  }
}

/// 全局便捷访问
final sl = ServiceLocator.instance;
