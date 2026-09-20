import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bilimusic/app/app_lifecycle.dart';
import 'package:bilimusic/app/desktop_tray.dart';
import 'package:bilimusic/app/app_navigator_key.dart';
import 'package:bilimusic/app/window_listener.dart';
import 'package:flutter/material.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/core/storage/database.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/logic/audio_handler.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'package:bilimusic/features/update/update_checker.dart';
import 'package:bilimusic/features/update/ui/update_dialog.dart';
import 'package:bilimusic/app/shells/app_shell.dart';
import 'package:bilimusic/features/storage/database_conflict_dialog.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';

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
  // 托盘建起来之后才拦截关闭：否则窗口关不掉，托盘里又没东西可点
  if (await DesktopTray.instance.initialize()) {
    await windowManager.setPreventClose(true);
  }
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

    // 桌面端把库从 sqflite 的默认落点搬进应用数据目录
    AppDatabase.directoryResolver = () async =>
        (await getApplicationSupportDirectory()).path;
  }

  // 数据库落点预检 —— 排在**窗口和 App 之前**。
  //
  // 用户手上可能不止一份库（旧落点跟着 cwd 走，见 core/storage/database_conflict.dart）。
  // 不止一份能读时要问用户，问完归档落败的、**重启进程**，新进程重扫一遍只会看到
  // 一份，于是走最朴素的「搬过去 / 打开」。放在这里而不是 App 内部，是因为重启时
  // 进程里必须什么都没有：`RestartMode.process` 是硬退出、不做析构，而且改名归档
  // 发生时不能有任何东西持有那些 `.db`（Windows 上 rename 被打开的文件会失败）。
  await _resolveDatabasePlacementIfNeeded();

  await _bootstrapApp();
}

/// 有落点冲突就问用户 + 归档 + 重启；没有冲突时立即返回。
///
/// 冲突这条路上这个函数**不应该返回**：用户选完之后 shell 会用
/// `RestartMode.process` 把进程换掉，新进程重扫一遍（那时盘上只剩一份，走最朴素的
/// 「搬过去 / 打开」）；换不掉时 shell 自己切到「请手动重新打开」。
Future<void> _resolveDatabasePlacementIfNeeded() async {
  final scan = await AppDatabase.preflightDatabaseLocation();
  if (scan == null) return;

  runApp(DatabaseConflictShell(scan: scan));

  // 走到这里说明进程没被换掉（正常路径永远到不了这行）
  // 让 shell 去提示用户手动重开。
  return Completer<void>().future;
}

/// 预检之后的常规启动：网络配置 → 组合根 → 音频服务 → 窗口 → `runApp`。
Future<void> _bootstrapApp() async {
  // 注入 Cookie 持久化(NetworkConfig 保持纯 Dart,便于 CLI/TUI 宿主复用)
  NetworkConfig.cookieLoader = () async =>
      (await SharedPreferences.getInstance()).getString('cookies');
  NetworkConfig.cookieSaver = (json) async =>
      (await SharedPreferences.getInstance()).setString('cookies', json);

  // 初始化网络配置
  await NetworkConfig.init();

  // 初始化just_audio_media_kit（仅在非Web和非Android/iOS平台上需要）
  if (PlatformHelper.isDesktop) {
    JustAudioMediaKit.ensureInitialized();
  }

  // 构造 Riverpod 容器，让依赖关系通过 ref.watch 编译期声明
  final container = ProviderContainer();
  // 登记给 AppLifecycleManager：退出时统一释放（摘托盘 → 收音频 → 释放容器 → 关窗口）
  AppLifecycleManager.instance.attachContainer(container);

  // 读取 playerCoordinator（首次读取会触发依赖图所有服务初始化）
  final coordinator = container.read(playerCoordinatorProvider);

  // 播放列表初始化（等 AppDatabase.instance.database）。
  //
  // **刻意不 await**：等在这里会把窗口的出现推迟到开库、甚至搬库之后。UI 读到的
  // 都是各 ValueNotifier 的初始空值，不会抛 StateError（那个只在 _dbChecked 上）。
  final playlistService = container.read(playlistServiceProvider);
  final playlistReady = playlistService.initialize();

  // 一次性把旧 SharedPreferences 列表数据迁入 playlist.db
  //
  // 同样刻意不 await：它内部会开库（可能还要先搬库）。放在 runApp 之后，启动顺序
  // 就是「窗口先出来 → 库打开 → 列表填充」。
  unawaited(AppDatabase.instance.migrateFromPrefsOnce());

  // 后台回填历史/收藏/当前列表中 cid 缺失的 item（不阻塞初始化）
  //
  // 先等 initialize 完成再回填：它内部用 `_dbChecked`，库还没开就会抛
  // StateError（未初始化访问）。等的是一个已经在跑的 Future，所以这里不额外
  // 阻塞任何东西。
  unawaited(
    playlistReady.then(
      (_) =>
          playlistService.backfillMissingCids(ensureCid: coordinator.ensureCid),
    ),
  );

  // 初始化音频服务并保存实例
  final audioHandler = await AudioService.init(
    builder: () => AudioHandlerConnector(coordinator, playlistService),
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
  container.read(notificationServiceProvider).initialize(audioHandler);

  // 登记给 AppLifecycleManager：退出前要 stop() 音频服务并显式释放 SMTC，
  // 否则系统媒体会话会被留到进程收尾阶段才析构 —— 那条路径在 Windows 上会崩
  // （audio_service_win#5，见 app_lifecycle.dart）
  AppLifecycleManager.instance.attachAudioHandler(audioHandler);

  // 初始化桌面窗口
  if (PlatformHelper.isDesktop) {
    await _setupMainWindow();
    // 托盘就绪后再接菜单内容（控制器在组合根里创建与释放）：
    // 菜单要读播放器状态，得等 Provider 容器就绪；没有托盘则无需创建。
    if (DesktopTray.instance.isReady) {
      DesktopTray.instance.useContent(container.read(trayMenuProvider));
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(audioHandler: audioHandler),
    ),
  );
}

/// 根Widget，负责管理播放器管理器实例
class MyApp extends ConsumerStatefulWidget {
  final BaseAudioHandler audioHandler;

  const MyApp({super.key, required this.audioHandler});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  // 全局key用于获取MaterialApp的context（与窗口监听器共用，见 app_navigator_key.dart）
  final GlobalKey<NavigatorState> _navigatorKey = appNavigatorKey;

  @override
  void initState() {
    super.initState();
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  ThemeMode _parseAppearance(String mode) {
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
    final settings = ref.watch(settingsProvider);
    final descriptor = ThemeRegistry.resolve(settings.theme);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'BiliMusic',
      debugShowCheckedModeBanner: false,
      theme: descriptor.light(),
      darkTheme: descriptor.dark(),
      themeMode: _parseAppearance(settings.appearance),
      // 数据库落点的冲突在 `main()` 里就已经问完了（那时候 App 还没构造），
      // 所以这里直接用 AppShell。
      home: const AppShell(),
    );
  }
}
