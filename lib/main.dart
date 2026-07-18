import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:bilimusic/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bilimusic/utils/window_listener.dart';
import 'package:flutter/material.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'package:bilimusic/core/database.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/audio_handler.dart';

import 'package:bilimusic/utils/network_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'package:bilimusic/utils/update_checker.dart';
import 'package:bilimusic/components/dialogs/update_dialog.dart';
import 'package:bilimusic/shells/app_shell.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/providers/settings_provider.dart';

Future<void> _setupMainWindow() async {
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = WindowOptions(
    size: const Size(1280, 720),
    minimumSize: const Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(BilimusicWindowListener());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Web 端 sqflite FFI 初始化
    databaseFactory = databaseFactoryFfiWeb;
    debugPrint('Web 端 sqflite 为实验性功能，可能存在兼容性问题');
  } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    // 桌面端 sqflite FFI 初始化
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 初始化网络配置
  await NetworkConfig.init();

  // 一次性把旧 SharedPreferences 列表数据迁入 playlist.db
  await AppDatabase.instance.migrateFromPrefsOnce();

  // 初始化just_audio_media_kit（仅在非Web和非Android/iOS平台上需要）
  if (PlatformHelper.isDesktop) {
    JustAudioMediaKit.ensureInitialized();
  }

  // 通过 ServiceLocator 初始化所有管理器和服务
  await sl.init();

  // 初始化音频服务并保存实例
  final audioHandler = await AudioService.init(
    builder: () => AudioHandlerConnector(sl.playerCoordinator),
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
  sl.notificationService.initialize(audioHandler);

  // 初始化桌面窗口
  if (PlatformHelper.isDesktop) {
    await _setupMainWindow();
  }

  runApp(ProviderScope(child: MyApp(audioHandler: audioHandler)));
}

/// 根Widget，负责管理播放器管理器实例
class MyApp extends ConsumerStatefulWidget {
  final BaseAudioHandler audioHandler;

  const MyApp({super.key, required this.audioHandler});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  // 添加全局key用于获取MaterialApp的context
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 确保playerManager已设置audioHandler
    // 重构后的播放器管理器不需要设置audioHandler
    WidgetsBinding.instance.addObserver(this);

    // 启动时检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    final updateChecker = UpdateChecker();
    final result = await updateChecker.compareVersions();
    if (result != null && mounted) {
      // 使用navigatorKey的context来显示对话框
      final navigatorContext = _navigatorKey.currentContext;
      debugPrint(
        'Update available: ${result.remoteVersion}\nChangelog:\n${result.newEntries.map((entry) => entry.toString()).join('\n')}',
      );
      if (navigatorContext != null) {
        await UpdateAvailableDialog.show(
          navigatorContext,
          newVersion: result.remoteVersion,
          changelog: result.newEntries,
        );
      }
    }
  }

  @override
  void dispose() {
    // 在应用关闭时释放播放器资源
    sl.playerCoordinator.dispose();
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
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'BiliMusic',
      debugShowCheckedModeBanner: false,
      theme: LucentTheme.lightTheme(),
      darkTheme: LucentTheme.darkTheme(),
      themeMode: _getThemeMode(ref.watch(settingsProvider).themeMode),
      home: const AppShell(),
    );
  }
}
