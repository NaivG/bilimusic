import 'package:bilimusic/app/app_navigator_key.dart';
import 'package:bilimusic/app/close_confirm_dialog.dart';
import 'package:bilimusic/app/desktop_tray.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:window_manager/window_manager.dart';

class BilimusicWindowListener extends WindowListener {
  /// 关闭确认弹窗是否正在展示（防止连点 X 叠出多层弹窗）
  bool _confirmDialogShowing = false;

  @override
  void onWindowClose() async {
    // 托盘不可用时保持原行为：直接退出（否则窗口关不掉，托盘里又没东西可点）
    if (!DesktopTray.instance.isReady) {
      await windowManager.destroy();
      return;
    }
    // SettingsManager 是单例，与 settingsManagerProvider 持有同一实例
    switch (SettingsManager().closeBehavior) {
      case SettingsManager.CLOSE_BEHAVIOR_MINIMIZE_TRAY:
        await DesktopTray.instance.hideToTray();
      case SettingsManager.CLOSE_BEHAVIOR_EXIT:
        await DesktopTray.instance.quit();
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
