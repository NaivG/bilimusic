import 'package:bilimusic/app/app_navigator_key.dart';
import 'package:bilimusic/app/app_lifecycle.dart';
import 'package:bilimusic/app/close_confirm_dialog.dart';
import 'package:bilimusic/app/desktop_tray.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:window_manager/window_manager.dart';

class BilimusicWindowListener extends WindowListener {
  /// 关闭确认弹窗是否正在展示（防止连点 X 叠出多层弹窗）
  bool _confirmDialogShowing = false;

  @override
  void onWindowClose() async {
    // 托盘不可用时没有「收进托盘」这个选项，直接走完整退出流程。
    //
    // 这里必须走 AppLifecycleManager.quit() 而不是 windowManager.destroy()：
    // destroy() 是 PostQuitMessage(0)（window_manager.cpp:233），跳过
    // WM_DESTROY → Win32Window::Destroy() → FlutterWindow::OnDestroy() 这条引擎析构路径，
    // 窗口/插件注册在「没析构」的状态下被进程退出带走，正是崩溃族一
    // （flutter_windows.dll + 0x1e240）的成因。quit() 内部的 `_quitting` 闸门同时挡住了
    // 「退出流程自己发的那次 close 再绕回这里」的递归。
    if (!DesktopTray.instance.isReady) {
      await AppLifecycleManager.instance.quit();
      return;
    }
    // SettingsManager 是单例，与 settingsManagerProvider 持有同一实例
    switch (SettingsManager().closeBehavior) {
      case SettingsManager.CLOSE_BEHAVIOR_MINIMIZE_TRAY:
        await DesktopTray.instance.hideToTray();
      case SettingsManager.CLOSE_BEHAVIOR_EXIT:
        await AppLifecycleManager.instance.quit();
      default: // prompt：弹窗询问本次关闭行为
        await _showCloseConfirmDialog();
    }
  }

  /// 关闭行为为「弹出提示」时的确认弹窗；界面尚未就绪时退回「收进托盘」。
  Future<void> _showCloseConfirmDialog() async {
    if (_confirmDialogShowing) return;
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      await DesktopTray.instance.hideToTray();
      return;
    }
    _confirmDialogShowing = true;
    try {
      await showCloseConfirmDialog(context);
    } finally {
      _confirmDialogShowing = false;
    }
  }

  @override
  void onWindowMinimize() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}
}
