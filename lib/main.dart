import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/audio_handler.dart';

import 'package:bilimusic/routes/app_routes.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/managers/settings_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/services/notification_service.dart';
import 'package:bilimusic/services/api_service.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/providers/playlist_manager_provider.dart';
import 'package:bilimusic/providers/player_manager_provider.dart';
import 'package:bilimusic/providers/search_state_provider.dart';
import 'package:bilimusic/shells/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化网络配置
  await NetworkConfig.init();

  // 初始化just_audio_media_kit（仅在非Web和非Android/iOS平台上需要）
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // 创建服务实例 - 使用DualAudioService支持交叉淡入淡出
  final dualAudioService = DualAudioService();
  final playlistService = PlaylistService();
  final notificationService = NotificationService();
  final apiService = ApiService();
  final settingsManager = SettingsManager();

  // 创建协调器
  final coordinator = PlayerCoordinator(
    audioService: dualAudioService,
    settingsManager: settingsManager,
    playlistService: playlistService,
    notificationService: notificationService,
    apiService: apiService,
  );

  // 初始化协调器
  await coordinator.initialize();

  // 初始化歌单管理器
  final playlistManager = PlaylistManager();
  await playlistManager.initialize();

  // 创建播放器管理器
  final playerManager = StreamingPlayerManager(coordinator);

  // 初始化音频服务并保存实例
  final audioHandler = await AudioService.init(
    builder: () => AudioHandlerConnector(playerManager),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'github.naivg.bilimusic.channel.audio',
      androidNotificationChannelName: 'BiliMusic Playback',
      androidNotificationChannelDescription:
          'BiliMusic Default Playback Channel',
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidResumeOnClick: true,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationClickStartsActivity: true,
    ),
  );

  // 初始化通知服务(音频处理器)
  notificationService.initialize(audioHandler);

  runApp(
    MyApp(
      audioHandler: audioHandler,
      playerManager: playerManager,
      playlistManager: playlistManager,
    ),
  );

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    doWhenWindowReady(() async {
      // 添加一个窗口按钮
      final desktopWindow = appWindow;
      desktopWindow.title = "BiliMusic";
      desktopWindow.alignment = Alignment.center;
      desktopWindow.minSize = Size(800, 600);
      desktopWindow.size = Size(1280, 720);
      desktopWindow.show();
    });
  }
}

/// 根Widget，负责管理播放器管理器实例
class MyApp extends StatefulWidget {
  final BaseAudioHandler audioHandler;
  final PlayerManager playerManager;
  final PlaylistManager playlistManager;

  const MyApp({
    super.key,
    required this.audioHandler,
    required this.playerManager,
    required this.playlistManager,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late PlayerManager _playerManager;
  late SettingsManager _settingsManager;
  late PlaylistManager _playlistManager;
  final SearchStateNotifier _searchStateNotifier = SearchStateNotifier();

  @override
  void initState() {
    super.initState();
    _playerManager = widget.playerManager;
    _playlistManager = widget.playlistManager;
    // 确保playerManager已设置audioHandler
    // 重构后的播放器管理器不需要设置audioHandler
    WidgetsBinding.instance.addObserver(this);

    // 初始化设置管理器
    _settingsManager = SettingsManager();
    _settingsManager.init();
  }

  @override
  void dispose() {
    // 在应用关闭时释放播放器资源
    _playerManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 可以在这里处理应用生命周期变化
    // 例如，在暂停时释放一些资源
  }

  // 根据设置获取主题模式
  ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 简约现代风格主题配置
    const modernBlue = Color(0xFF2563EB); // 现代蓝

    return PlayerManagerProvider(
      playerManager: _playerManager,
      child: PlaylistManagerProvider(
        playlistManager: _playlistManager,
        child: SearchStateProvider(
          searchState: _searchStateNotifier,
          child: MaterialApp(
            title: 'BiliMusic',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: modernBlue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            // 统一圆角风格
            cardTheme: CardThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            // 圆角按钮风格
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            // 圆角输入框
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: modernBlue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            // 深色主题统一圆角
            cardTheme: CardThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
          themeMode: _getThemeMode(_settingsManager.themeMode),
          home: AppShell(
            playerManager: _playerManager,
            playlistManager: _playlistManager,
          ),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    ),
    );
  }
}

