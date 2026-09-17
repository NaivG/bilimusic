import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 桌面端窗口拖动区。
///
/// 应用窗口用 `TitleBarStyle.hidden` 隐藏了原生标题栏（见 `main.dart`），
/// 移窗完全依赖自绘的标题栏：把本组件包在标题栏外层，整条标题栏
/// （含没有子控件的空白处）都能起拖。
///
/// - 默认 [HitTestBehavior.opaque]：空白处也接受指针，不依赖 Material 的
///   命中吸收。`forceMaterialTransparency: true` 的透明 AppBar 只有子控件
///   能命中，包一层 opaque 才整条可拖。
/// - 只挂 `onPanStart`，不挂 `onDoubleTap`：双击识别器会在手势竞技场里
///   `hold(pointer)`，子控件的单击要等 `kDoubleTapTimeout`(300ms) 才响应。
///   需要「双击最大化」的标题栏请用 Stack 垫底层单独挂（见 [LandscapeTitleBar]）。
/// - 子控件仍优先命中：起拖于按钮上时窗口跟着走，单击按钮不受影响。
/// - 非桌面平台原样返回 [child]，移动端不引入窗口概念。
class WindowDragArea extends StatelessWidget {
  /// 整块可拖动的区域，通常是标题栏。
  final Widget child;

  /// 命中行为，默认 [HitTestBehavior.opaque]。
  final HitTestBehavior behavior;

  const WindowDragArea({
    super.key,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  Widget build(BuildContext context) {
    if (!PlatformHelper.isDesktop) return child;

    return GestureDetector(
      behavior: behavior,
      onPanStart: (_) => windowManager.startDragging(),
      child: child,
    );
  }
}
