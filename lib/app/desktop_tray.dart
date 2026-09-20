import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 托盘右键菜单的内容来源。
///
/// 托盘基础设施只负责「图标与时机」（什么时候建图标、什么时候刷新），
/// 有哪些条目、文案与勾选态怎么变由实现方决定（见 `tray_menu.dart`），
/// 这样本文件不必认识播放器。
abstract interface class TrayMenuContent {
  /// 菜单本体；返回 null 表示这次没能建出菜单（托盘就不给右键菜单）。
  Menu? get menu;

  /// 托盘图标悬停提示（通常是当前曲目）。
  String get tooltip;

  /// 状态变化时调用：只改条目的文案 / 勾选态 / 可用性，不动菜单结构。
  void refresh();

  /// 释放菜单与条目句柄。必须可重入——托盘与组合根都会释放一次。
  void dispose();
}

/// 桌面端系统托盘：把窗口「最小化 / 关闭」收进托盘，并提供右键菜单。
///
/// 只有托盘图标真的创建成功（[isReady]）时，窗口监听器才会接管最小化与关闭；
/// 托盘不可用时保持原来的行为——否则用户会既看不到托盘图标、又关不掉窗口。
class DesktopTray {
  DesktopTray._();

  /// 单例：窗口监听器与托盘监听器要共享同一份「托盘是否可用」的状态。
  static final DesktopTray instance = DesktopTray._();

  /// Windows 托盘按惯例用 .ico，其余桌面平台用 png。
  static String get _iconAsset =>
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/ic_launcher.png';

  TrayIcon? _trayIcon;
  TrayMenuContent? _content;

  /// 最近一次写给原生层的提示；相同就不重复写（crossfade 倒计时会每秒刷新一次菜单）。
  String? _tooltip;

  bool _ready = false;

  /// 托盘是否可用（创建成功才为 true）
  bool get isReady => _ready;

  /// 创建托盘图标。失败只记日志并返回 false，不抛异常。
  ///
  /// 这里只建图标本身，右键菜单由 [useContent] 在组合根备好内容后挂上
  /// （菜单要读播放器状态，得等 Provider 容器就绪）。
  Future<bool> initialize() async {
    if (_ready) return true;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return false;
    }

    try {
      final image = ImageAsset.fromAsset(_iconAsset);
      if (image == null) {
        debugPrint('[Tray] 图标资源缺失：$_iconAsset');
        return false;
      }

      final icon = TrayIcon.create();
      if (icon == null) {
        debugPrint('[Tray] TrayIcon.create() 返回空，托盘不可用');
        return false;
      }

      icon.icon = image;
      icon.setTooltip('BiliMusic');
      icon.addListener(_onTrayEvent);
      // Windows 默认是 ContextMenuTrigger.none，不设置的话右键不弹菜单
      icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      // 新建的托盘图标默认不可见
      if (!icon.setVisible(true)) {
        debugPrint('[Tray] 托盘图标显示失败');
        icon.dispose();
        return false;
      }

      _trayIcon = icon;
      _tooltip = 'BiliMusic';
      _ready = true;
      debugPrint('[Tray] 托盘就绪：左键显示/隐藏窗口，右键弹出菜单');
      return true;
    } catch (error) {
      debugPrint('[Tray] 托盘初始化失败：$error');
      return false;
    }
  }

  /// 挂上右键菜单内容。托盘尚未就绪时只记日志——没图标就没有菜单可挂。
  void useContent(TrayMenuContent content) {
    final icon = _trayIcon;
    final menu = content.menu;
    if (!_ready || icon == null) {
      debugPrint('[Tray] 托盘未就绪，忽略菜单内容');
      return;
    }
    if (menu == null) {
      debugPrint('[Tray] 菜单创建失败，托盘没有右键菜单');
      return;
    }
    _content?.dispose();
    _content = content;
    icon.setContextMenu(menu);
    _applyTooltip(content.tooltip);
    refreshContent();
    debugPrint('[Tray] 菜单内容就绪：${menu.itemCount} 项');
  }

  /// 刷新菜单：条目文案 / 勾选态由内容自己重算，顺带同步托盘提示。
  void refreshContent() {
    final content = _content;
    if (!_ready || content == null) return;
    content.refresh();
    _applyTooltip(content.tooltip);
  }

  void _applyTooltip(String tooltip) {
    if (_tooltip == tooltip) return;
    _tooltip = tooltip;
    _trayIcon?.setTooltip(tooltip);
  }

  /// 隐藏窗口到托盘（任务栏按钮一起消失，托盘图标保留）。
  Future<void> hideToTray() async {
    await windowManager.hide();
  }

  /// 从托盘恢复窗口并置前。
  Future<void> showWindow() async {
    // 最小化后被收进托盘的窗口，show() 不会自己还原
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// 左键点托盘图标：窗口可见就收起，不可见就显示。
  Future<void> toggleWindow() async {
    if (await windowManager.isVisible()) {
      await hideToTray();
    } else {
      await showWindow();
    }
  }

  /// 真正退出：先摘掉托盘图标（避免任务栏留下幽灵图标），再关窗口。
  Future<void> quit() async {
    await dispose();
    // 关闭拦截还开着的话，destroy 之外的关闭路径又会被解释成「收进托盘」
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// 释放托盘图标与菜单内容。之后 [isReady] 为 false，窗口恢复默认的关闭行为。
  Future<void> dispose() async {
    _ready = false;
    final icon = _trayIcon;
    final content = _content;
    _trayIcon = null;
    _content = null;
    _tooltip = null;
    try {
      icon?.setVisible(false);
      // 先释放菜单句柄再销毁托盘图标——与 tray_manager 自己的 destroy() 同序，
      // 免得原生层在图标销毁时再去引用已经释放的菜单。
      content?.dispose();
      icon?.dispose();
    } catch (error) {
      debugPrint('[Tray] 释放托盘失败：$error');
    }
  }

  void _onTrayEvent(TrayIconEvent event) {
    switch (event) {
      case TrayIconClickedEvent():
        unawaited(toggleWindow());
      case TrayIconDoubleClickedEvent():
        unawaited(showWindow());
      case TrayIconRightClickedEvent():
        // 右键菜单由 setContextMenuTrigger 自己弹出，这里不用管
        break;
    }
  }
}
