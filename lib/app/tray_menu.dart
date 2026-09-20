import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:bilimusic/app/app_lifecycle.dart';
import 'package:bilimusic/app/desktop_tray.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/play_mode.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 菜单条目在某一时刻的呈现状态。
///
/// 用记录（record）做结构相等比较：只有真的变了才写回原生条目——
/// 播放状态每秒都可能变化（crossfade 倒计时），无脑重写不值当。
typedef _MenuSnapshot = ({
  String nowPlaying,
  bool hasQueue,
  bool hasCurrent,
  bool isPlaying,
  bool isFavorite,
  PlayMode playMode,
});

/// 托盘右键菜单内容：曲目信息 + 播放控制 + 收藏 / 播放模式 + 页面入口 + 退出。
///
/// 菜单结构在创建时定死，之后只改条目的文案 / 勾选态 / 可用性：原生条目支持热改，
/// 而结构性增删要重建整个 context menu（菜单可能正被展开），代价与风险都不值当。
///
/// 窗口收进托盘后整个 Dart 侧照常运行，所以这些动作都直接打在服务上，
/// 不依赖任何 Widget 或 BuildContext。
class TrayMenu implements TrayMenuContent {
  TrayMenu({
    required PlayerCoordinator coordinator,
    required PlaylistService playlistService,
  }) : _coordinator = coordinator,
       _playlistService = playlistService {
    _menu = _buildMenu();
    if (_menu == null) return;
    _listenPlayerState();
  }

  /// 无歌可播时顶部那行显示的文案。
  static const String _idleLabel = '未在播放';

  /// 设置页在顶层 tab 中的下标（见 ShellPageManager.goToTab / selectedTabIndex）。
  static const int _settingsTabIndex = 3;

  /// 播放队列页用的歌单 id：不是系统歌单，页面按传进去的 songs 走临时歌单分支。
  static const String _queuePlaylistId = 'queue';

  /// 顶部曲目行与托盘提示的截断长度：原生菜单会被屏幕宽度裁掉，先自己收一下。
  static const int _menuLabelMaxLength = 48;
  static const int _tooltipMaxLength = 100;

  static const Map<PlayMode, String> _playModeLabels = {
    PlayMode.sequential: '顺序播放',
    PlayMode.loop: '单曲循环',
    PlayMode.shuffle: '随机播放',
  };

  final PlayerCoordinator _coordinator;
  final PlaylistService _playlistService;

  Menu? _menu;
  Menu? _playModeMenu;

  /// 所有建出来的条目：释放时逐个 dispose（子菜单里的也算）。
  final List<MenuItem> _items = [];
  final Map<PlayMode, MenuItem> _playModeItems = {};

  MenuItem? _nowPlayingItem;
  MenuItem? _togglePlayItem;
  MenuItem? _previousItem;
  MenuItem? _nextItem;
  MenuItem? _favoriteItem;
  MenuItem? _queueItem;

  _MenuSnapshot? _applied;
  bool _disposed = false;

  @override
  Menu? get menu => _menu;

  @override
  String get tooltip {
    final music = _coordinator.currentMusic;
    if (music == null) return 'BiliMusic';
    return _ellipsize('BiliMusic · ${_trackLabel(music)}', _tooltipMaxLength);
  }

  @override
  void refresh() {
    if (_disposed) return;
    final snapshot = _readSnapshot();
    if (snapshot == _applied) return;
    _applied = snapshot;

    _nowPlayingItem?.label = snapshot.nowPlaying;
    _togglePlayItem
      ?..label = snapshot.isPlaying ? '暂停' : '播放'
      ..isEnabled = snapshot.hasCurrent;
    _previousItem?.isEnabled = snapshot.hasQueue;
    _nextItem?.isEnabled = snapshot.hasQueue;
    _favoriteItem
      ?..isEnabled = snapshot.hasCurrent
      ..state = _state(snapshot.isFavorite);
    _queueItem?.isEnabled = snapshot.hasQueue;
    for (final entry in _playModeItems.entries) {
      entry.value.state = _state(entry.key == snapshot.playMode);
    }
  }

  @override
  void dispose() {
    // 托盘与组合根都会释放，重入必须无害（MenuItem.dispose 二次调用会重复释放句柄）
    if (_disposed) return;
    _disposed = true;
    _unlistenPlayerState();
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _playModeItems.clear();
    _playModeMenu?.dispose();
    _menu?.dispose();
    _menu = null;
    _playModeMenu = null;
  }

  // ============ 菜单构建 ============

  Menu? _buildMenu() {
    final menu = Menu.create();
    if (menu == null) {
      debugPrint('[Tray] 右键菜单创建失败');
      return null;
    }

    _nowPlayingItem = _add(
      menu,
      _idleLabel,
      MenuItemType.normal,
      enabled: false,
    );
    menu.addSeparator();

    _togglePlayItem = _add(
      menu,
      '播放',
      MenuItemType.normal,
      onClick: _togglePlayPause,
    );
    _previousItem = _add(
      menu,
      '上一首',
      MenuItemType.normal,
      onClick: () => _run(_coordinator.playPrevious),
    );
    _nextItem = _add(
      menu,
      '下一首',
      MenuItemType.normal,
      onClick: () => _run(_coordinator.playNext),
    );
    menu.addSeparator();

    _favoriteItem = _add(
      menu,
      '收藏本曲',
      MenuItemType.checkbox,
      onClick: _toggleFavorite,
    );
    _buildPlayModeItems(menu);
    menu.addSeparator();

    _add(
      menu,
      '显示主窗口',
      MenuItemType.normal,
      onClick: () => _run(DesktopTray.instance.showWindow),
    );
    _queueItem = _add(menu, '播放队列', MenuItemType.normal, onClick: _openQueue);
    _add(menu, '设置', MenuItemType.normal, onClick: _openSettings);
    menu.addSeparator();

    _add(menu, '退出 BiliMusic', MenuItemType.normal, onClick: _quit);
    return menu;
  }

  void _buildPlayModeItems(Menu parent) {
    final modeMenu = Menu.create();
    if (modeMenu == null) {
      debugPrint('[Tray] 播放模式子菜单创建失败');
      return;
    }
    final modeItem = _add(
      parent,
      '播放模式',
      MenuItemType.submenu,
      submenu: modeMenu,
    );
    if (modeItem == null) {
      // 没能挂进菜单，子菜单句柄得自己收掉
      modeMenu.dispose();
      return;
    }
    _playModeMenu = modeMenu;

    for (final mode in PlayMode.values) {
      final item = _add(
        modeMenu,
        _playModeLabels[mode]!,
        MenuItemType.checkbox,
        onClick: () => _coordinator.setPlayMode(mode),
      );
      if (item != null) _playModeItems[mode] = item;
    }
  }

  /// 建一个条目并挂进 [parent]；原生创建失败时返回 null
  /// （少一个条目，但不至于把整份菜单拖垮）。
  MenuItem? _add(
    Menu parent,
    String label,
    MenuItemType type, {
    Menu? submenu,
    bool enabled = true,
    void Function()? onClick,
  }) {
    final item = MenuItem.createWithLabelAndType(label, type);
    if (item == null) {
      debugPrint('[Tray] 菜单项创建失败：$label');
      return null;
    }
    item.isEnabled = enabled;
    // 子菜单必须在入菜单之前挂上：原生侧按「加入时有没有子菜单」决定这一项是
    // 弹出项（MF_POPUP，自己没有命令 ID）还是普通命令项，事后再挂要多走一遍
    // 删除重插，而且这一项此后不再有命令 ID，改文案 / 勾选态都会落空。
    if (submenu != null) item.submenu = submenu;
    if (onClick != null) {
      item.addListener((event) {
        if (event is MenuItemClickedEvent) onClick();
      });
    }
    parent.addItem(item);
    _items.add(item);
    return item;
  }

  // ============ 状态同步 ============

  void _listenPlayerState() {
    _coordinator.playlist.addListener(_onPlayerStateChanged);
    _coordinator.currentIndexNotifier.addListener(_onPlayerStateChanged);
    _coordinator.playerState.addListener(_onPlayerStateChanged);
    _coordinator.playMode.addListener(_onPlayerStateChanged);
    _coordinator.favorites.addListener(_onPlayerStateChanged);
  }

  void _unlistenPlayerState() {
    _coordinator.playlist.removeListener(_onPlayerStateChanged);
    _coordinator.currentIndexNotifier.removeListener(_onPlayerStateChanged);
    _coordinator.playerState.removeListener(_onPlayerStateChanged);
    _coordinator.playMode.removeListener(_onPlayerStateChanged);
    _coordinator.favorites.removeListener(_onPlayerStateChanged);
  }

  void _onPlayerStateChanged() => DesktopTray.instance.refreshContent();

  _MenuSnapshot _readSnapshot() {
    final music = _coordinator.currentMusic;
    return (
      nowPlaying: music == null ? _idleLabel : _menuLabel(_trackLabel(music)),
      hasQueue: _coordinator.playlistLength > 0,
      hasCurrent: music != null,
      isPlaying: _coordinator.isPlaying,
      isFavorite: music != null && _playlistService.isFavorite(music),
      playMode: _coordinator.playMode.value,
    );
  }

  // ============ 菜单动作 ============

  void _togglePlayPause() => _run(() async {
    switch (_coordinator.playerState.value) {
      case PlayerPlaying():
        await _coordinator.pause();
      case PlayerPaused():
      case PlayerCompleted():
      case PlayerBuffering():
        await _coordinator.resume();
      case PlayerIdle():
        // 从未起播 / 已停止：从当前索引重新取流播放
        await _coordinator.playCurrentTrack();
    }
  });

  void _toggleFavorite() => _run(() async {
    final music = _coordinator.currentMusic;
    if (music == null) return;
    await _playlistService.toggleFavorite(music);
  });

  void _openQueue() => _run(() async {
    final songs = _coordinator.playlist.value;
    if (songs.isEmpty) return;
    await DesktopTray.instance.showWindow();
    ShellPageManager.instance.goToPlaylist(
      playlistId: _queuePlaylistId,
      songs: songs,
      playlistName: '播放队列',
    );
  });

  void _openSettings() => _run(() async {
    await DesktopTray.instance.showWindow();
    ShellPageManager.instance.goToTab(_settingsTabIndex);
  });

  /// 退出要等菜单自己的消息循环跑完：在菜单回调里同步销毁托盘图标会崩。
  void _quit() => Timer.run(() => _run(AppLifecycleManager.instance.quit));

  /// 菜单回调不能把异常抛回原生层——那会打断原生的菜单消息循环。
  void _run(Future<void> Function() action) {
    unawaited(
      action().catchError((Object error) {
        debugPrint('[Tray] 菜单动作失败：$error');
      }),
    );
  }

  // ============ 文案 ============

  static MenuItemState _state(bool checked) =>
      checked ? MenuItemState.checked : MenuItemState.unchecked;

  static String _trackLabel(Music music) => music.artist.isEmpty
      ? '♪ ${music.title}'
      : '♪ ${music.title} — ${music.artist}';

  /// 菜单文案：先按菜单宽度截断，再按平台转义。
  ///
  /// Win32 菜单把 `&` 当助记符前缀（`&B` 会变成带下划线的 B，`&` 本身被吃掉），
  /// 曲名里的 `&` 得写成 `&&` 才显示得出来；GTK / NSMenu 不认这套，
  /// 一起转义反而会多出一个 `&`，所以只在 Windows 上做。
  static String _menuLabel(String text) {
    final trimmed = _ellipsize(text, _menuLabelMaxLength);
    return PlatformHelper.isWindows ? trimmed.replaceAll('&', '&&') : trimmed;
  }

  static String _ellipsize(String text, int maxLength) =>
      text.length <= maxLength ? text : '${text.substring(0, maxLength - 1)}…';
}
