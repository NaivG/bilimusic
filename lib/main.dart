import 'dart:io';
import 'dart:ui';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 似乎不能去除这行
import 'package:bilimusic/components/audio_player_manager.dart';
import 'package:bilimusic/components/mini_player.dart';
import 'package:bilimusic/pages/home_page.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/pages/profile_page.dart'; // 导入我的页面
import 'package:bilimusic/pages/settings_page.dart'; // 导入设置页面
import 'package:bilimusic/routes/app_routes.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:audio_service/audio_service.dart';
import 'package:bilimusic/components/playlist_manager.dart'; // 导入播放列表管理器
import 'package:bilimusic/components/player_manager.dart'; // 导入PlayerManager相关类
import 'package:bilimusic/components/play_list.dart';
import 'package:bilimusic/utils/settings_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化网络配置
  await NetworkConfig.init();

  // 初始化just_audio_media_kit（仅在非Web和非Android/iOS平台上需要）
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // 先创建播放管理器
  final playerManager = AudioPlayerManager();

  // 初始化音频服务并保存实例
  final audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(playerManager),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'github.naivg.bilimusic.channel.audio',
      androidNotificationChannelName: 'BiliMusic Playback',
      androidResumeOnClick: true,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationClickStartsActivity: true,
    ),
  );

  // 将audioHandler设置给playerManager
  playerManager.setAudioHandler(audioHandler);

  runApp(MyApp(audioHandler: audioHandler, playerManager: playerManager));

  if (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) {
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
  final AudioPlayerManager playerManager;

  const MyApp({super.key, required this.audioHandler, required this.playerManager});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late AudioPlayerManager _playerManager;
  late BaseAudioHandler _audioHandler; // 新增
  late SettingsManager _settingsManager;

  @override
  void initState() {
    super.initState();
    _playerManager = widget.playerManager;
    _audioHandler = widget.audioHandler;
    // 确保playerManager已设置audioHandler
    _playerManager.setAudioHandler(_audioHandler);
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
    return PlayerManagerProvider(
      playerManager: _playerManager,
      child: MaterialApp(
        title: 'BiliMusic',
        debugShowCheckedModeBanner: false, // 移除Debug标签
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          // 在深色主题中，确保文本和图标在背景上有足够的对比度
          textTheme: const TextTheme(
            titleLarge: TextStyle(color: Colors.white),
            titleMedium: TextStyle(color: Colors.white),
            bodyLarge: TextStyle(color: Colors.white70),
            bodyMedium: TextStyle(color: Colors.white70),
          ),
        ),
        themeMode: _getThemeMode(_settingsManager.themeMode),
        home: const MyHomePage(),
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}

/// 提供播放器管理器的InheritedWidget
class PlayerManagerProvider extends InheritedWidget {
  final AudioPlayerManager playerManager;

  const PlayerManagerProvider({
    super.key,
    required this.playerManager,
    required super.child,
  });

  static AudioPlayerManager of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<PlayerManagerProvider>();
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  late AudioPlayerManager _playerManager;
  late SettingsManager _settingsManager;
  List<Widget> _pages = []; // 初始化为空列表
  bool _isPcMode = false;
  final bool _isPcPlatform = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _playerManager = PlayerManagerProvider.of(context);
      _settingsManager = SettingsManager();
      _isPcMode = _settingsManager.pcMode;

      // 确保只初始化一次
      if (_pages.isEmpty) {
        _pages = [
          HomePage(playerManager: _playerManager),
          SearchPage(playerManager: _playerManager),
          ProfilePage(playerManager: _playerManager),
          SettingsPage(),
        ];
        // 触发UI更新
        if (mounted) setState(() {});
      }
    } catch (e) {
      // 添加错误处理
      debugPrint("Error initializing player manager: $e");
      // 可以在这里设置错误状态
    }
  }

  @override
  void initState() {
    super.initState();
    // 初始化时检查播放列表是否为空，决定是否显示迷你播放器
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    // });
    if (kDebugMode) { // 测试模式
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          // false = user must tap button, true = tap outside dialog
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              icon: Icon(
                  Icons.warning,
                  size: 32.0
              ),
              title: Text('哎呀 o(><；)o'),
              content: Text('你正在使用测试版本，可能会存在一些未知bug，包括界面可能存在渲染问题，新功能可能无法正常使用等等。\n如果遇到问题，请反馈给开发者。'),
              contentPadding: EdgeInsets.all(16.0),
              actions: <Widget>[
                TextButton(
                  child: Text('我知道啦'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(); // Dismiss alert dialog
                  },
                ),
              ],
            );
          },
        );
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openPlayList() {
    showModalBottomSheet(
      context: context,
      builder: (context) => PlayListSheet(
        playerManager: _playerManager,
        onTrackSelect: (index) {
          _playerManager.playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 显示加载指示器而不是空白容器
    if (_pages.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 检查是否应该启用平板模式
    bool isTabletMode = false;
    switch (_settingsManager.tabletMode) {
      case 'on':
        isTabletMode = true;
        break;
      case 'off':
        isTabletMode = false;
        break;
      case 'auto':
      default:
        // 自动模式：检查屏幕宽度是否大于600dp（平板阈值）
        isTabletMode = MediaQuery.of(context).size.shortestSide >= 600;
        break;
    }

    if (isTabletMode) {
      // 平板模式布局
      return Scaffold(
        appBar: _isPcPlatform
                ? _buildPCBar(context)
                : null,
        body: Row(
          children: [
            // 侧边导航栏
            _isPcMode
            ? SizedBox(width: 0,)
            : SizedBox(
              width: 80,
              child: NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home),
                    label: Text('首页'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search),
                    label: Text('搜索'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.person),
                    label: Text('我的'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('设置'),
                  ),
                ],
              ),
            ),
            // 主内容区域
            Expanded(
              child: Stack(
                children: [
                  _pages[_selectedIndex],
                  // 平板模式下的悬浮迷你播放器
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 20,
                    child: Center(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.8, // 限制迷你播放器宽度
                        child: MiniPlayerComponent(
                          playerManager: _playerManager,
                          onExpand: () {
                            // 实现迷你播放器展开逻辑
                          },
                          onPlayList: _openPlayList,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // 手机模式布局
      return Scaffold(
        appBar: _isPcPlatform
            ? _buildPCBar(context)
            : null,
        body: _pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置')
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
        // 统一处理迷你播放器
        bottomSheet:
          MiniPlayerComponent(
            playerManager: _playerManager,
            onExpand: () {
              // 实现迷你播放器展开逻辑
            },
            onPlayList: _openPlayList,
          ),
      );
    }
  }

  PreferredSizeWidget _buildPCBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PreferredSize(
      preferredSize: const Size.fromHeight(40.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900]! : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1.0,
            ),
          ),
        ),
        child: MoveWindow(
          child: Row(
            children: [
              // 左侧应用图标和标题
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/ic_launcher.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'BiliMusic',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[800],
                        fontFamily: 'CabinSketch',
                      ),
                    ),
                  ],
                ),
              ),

              // 导航菜单
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _NavBarItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      label: '首页',
                      isActive: _selectedIndex == 0,
                      onTap: () => _onItemTapped(0),
                    ),
                    _NavBarItem(
                      icon: Icons.search_outlined,
                      activeIcon: Icons.search,
                      label: '搜索',
                      isActive: _selectedIndex == 1,
                      onTap: () => _onItemTapped(1),
                    ),
                    _NavBarItem(
                      icon: Icons.person_outlined,
                      activeIcon: Icons.person,
                      label: '我的',
                      isActive: _selectedIndex == 2,
                      onTap: () => _onItemTapped(2),
                    ),
                    _NavBarItem(
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings,
                      label: '设置',
                      isActive: _selectedIndex == 3,
                      onTap: () => _onItemTapped(3),
                    ),
                  ],
                ),
              ),

              // 窗口控制按钮
              Row(
                children: [
                  // 最小化按钮
                  WindowButton(
                    colors: WindowButtonColors(
                      iconNormal: isDark ? Colors.grey[400] : Colors.grey[700],
                      iconMouseOver: isDark ? Colors.grey[300] : Colors.grey[800],
                      iconMouseDown: isDark ? Colors.grey[200] : Colors.grey[900],
                      mouseOver: isDark ? Colors.grey[800] : Colors.grey[200],
                      mouseDown: isDark ? Colors.grey[700] : Colors.grey[300],
                    ),
                    onPressed: () => appWindow.minimize(),
                    iconBuilder: (buttonContext) => const Icon(Icons.minimize, size: 14),
                  ),

                  // 最大化/恢复按钮
                  WindowButton(
                    colors: WindowButtonColors(
                      iconNormal: isDark ? Colors.grey[400] : Colors.grey[700],
                      iconMouseOver: isDark ? Colors.grey[300] : Colors.grey[800],
                      iconMouseDown: isDark ? Colors.grey[200] : Colors.grey[900],
                      mouseOver: isDark ? Colors.grey[800] : Colors.grey[200],
                      mouseDown: isDark ? Colors.grey[700] : Colors.grey[300],
                    ),
                    onPressed: () {
                      if (appWindow.isMaximized) {
                        appWindow.restore();
                      } else {
                        appWindow.maximize();
                      }
                    },
                    iconBuilder: (buttonContext) => Icon(
                      appWindow.isMaximized ? Icons.filter_none : Icons.crop_square,
                      size: 14,
                    ),
                  ),

                  // 关闭按钮
                  WindowButton(
                    colors: WindowButtonColors(
                      iconNormal: isDark ? Colors.grey[400] : Colors.grey[700],
                      iconMouseOver: Colors.white,
                      iconMouseDown: Colors.white,
                      mouseOver: Colors.red,
                      mouseDown: Colors.red[700],
                    ),
                    onPressed: () {
                      _playerManager.stop();
                      appWindow.close();
                    },
                    iconBuilder: (buttonContext) => const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  size: 18,
                  color: isActive
                      ? theme.colorScheme.primary
                      : (isDark ? Colors.grey[400] : Colors.grey[700]),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? theme.colorScheme.primary
                        : (isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}