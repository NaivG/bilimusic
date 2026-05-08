import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端画中画（小窗模式）服务
/// 管理 PiP 模式的生命周期和窗口几何状态
class PipService extends ChangeNotifier {
  static final PipService _instance = PipService._();
  factory PipService() => _instance;
  PipService._();

  bool _isPipMode = false;
  bool get isPipMode => _isPipMode;

  // 保存的窗口状态
  Size? _savedSize;
  Offset? _savedPosition;
  bool? _wasMaximized;

  // PiP 防重复触发
  bool _isToggling = false;

  // PiP 窗口常量
  static const double pipWidth = 420.0;
  static const double pipHeight = 160.0;
  static const Size pipMinimumSize = Size(320, 160);

  /// 切换 PiP 模式
  Future<void> toggle() async {
    if (_isToggling) return;
    _isToggling = true;
    try {
      if (_isPipMode) {
        await exitPipMode();
      } else {
        await enterPipMode();
      }
    } finally {
      _isToggling = false;
    }
  }

  /// 进入 PiP 模式
  Future<void> enterPipMode() async {
    try {
      // 1. 保存当前窗口状态
      _wasMaximized = await windowManager.isMaximized();
      if (_wasMaximized!) {
        await windowManager.unmaximize();
      }
      _savedPosition = await windowManager.getPosition();
      _savedSize = await windowManager.getSize();

      // 2. 隐藏窗口，避免缩放动画
      await windowManager.hide();

      // 3. 标记 PiP 模式状态
      _isPipMode = true;
      notifyListeners();

      // 4. 缩放窗口到 PiP 大小
      await windowManager.setMinimumSize(pipMinimumSize);

      // 计算 PiP 窗口位置（居中于原窗口区域）
      final centerX = _savedPosition!.dx +
          (_savedSize!.width - pipWidth) / 2;
      final centerY = _savedPosition!.dy +
          (_savedSize!.height - pipHeight) / 2;
      await windowManager.setPosition(Offset(centerX, centerY));
      await windowManager.setSize(const Size(pipWidth, pipHeight));

      // 5. 恢复显示
      await windowManager.show();

      // 6. 置顶窗口
      await windowManager.setAlwaysOnTop(true);

    } catch (e) {
      // 出错时确保恢复显示
      await windowManager.show();
      debugPrint('PipService.enterPipMode error: $e');
      _isPipMode = false;
      notifyListeners();
    }
  }

  /// 退出 PiP 模式
  Future<void> exitPipMode() async {
    try {
      // 1. 取消置顶
      await windowManager.setAlwaysOnTop(false);

      // 2. 恢复原始窗口大小和位置
      await windowManager.setMinimumSize(const Size(800, 600));
      if (_savedSize != null) {
        await windowManager.setSize(_savedSize!);
      }
      if (_savedPosition != null) {
        await windowManager.setPosition(_savedPosition!);
      }
      if (_wasMaximized == true) {
        await windowManager.maximize();
      }

      _isPipMode = false;
      notifyListeners();
    } catch (e) {
      debugPrint('PipService.exitPipMode error: $e');
      _isPipMode = false;
      notifyListeners();
    }
  }
}
