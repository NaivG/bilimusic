import 'package:audio_service/audio_service.dart';
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_service_win/audio_service_win.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:bilimusic/app/desktop_tray.dart';

/// 应用生命周期：退出时的统一收尾。
///
/// 与启动时的组合根（`main.dart`）对称——启动按顺序把服务立起来，退出按相反的顺序
/// 收回去；顺序本身有讲究，所以「退出应用」只能有一个入口（[quit]）。
///
/// 之所以是单例而不是 Provider：容器本身就要在这里被释放，退出流程不能依赖容器；
/// 窗口 / 托盘这些原生资源本来也在容器之外（同 [DesktopTray]）。
/// 容器与音频句柄在 `main.dart` 启动时登记（[attachContainer] / [attachAudioHandler]）。
class AppLifecycleManager {
  AppLifecycleManager._();

  /// 单例：退出是有序的一次性流程，多处各持一份会退化成互相抢资源的竞态。
  static final AppLifecycleManager instance = AppLifecycleManager._();

  /// 组合根建好的 Provider 容器；[quit] 里统一 `dispose()`，触发
  /// `app_providers.dart` 中登记的所有 `ref.onDispose` 回调。
  ProviderContainer? _container;

  /// `AudioService.init()` 返回的 handler；退出前要 `stop()` 一次。
  BaseAudioHandler? _audioHandler;

  /// 退出流程是否已经开始。
  ///
  /// [quit] 自己就会触发一次窗口 close 回调（退出路上 `isReady` 已是 false，
  /// 窗口监听器会兜回 [quit]），没有这个闸门就会递归回来二次释放；
  /// 也兼作「极早期退出」的保护：容器 / 句柄还没登记时同样能走完流程。
  bool _quitting = false;

  /// 登记 Provider 容器（`main.dart` 建好容器后立刻调用）。
  void attachContainer(ProviderContainer container) {
    _container = container;
  }

  /// 登记音频 handler（`main.dart` 在 `AudioService.init()` 之后调用）。
  void attachAudioHandler(BaseAudioHandler handler) {
    _audioHandler = handler;
  }

  /// 退出应用：摘托盘 → 收音频 → 释放容器 → 关窗口。可重入，重复调用直接返回。
  ///
  /// 顺序要点：
  /// 1. **先摘托盘再解除关闭拦截**——在音频收尾与容器释放完成前，关闭拦截必须还开着，
  ///    否则这期间用户再点一次关闭就会让窗口被原生路径直接销毁，后面的释放全被跳过
  ///    （此时 `isReady` 已是 false，窗口监听器的兜底分支会回到 [quit]，被 [_quitting] 挡下）。
  /// 2. **音频在容器之前**——handler 由容器里的服务驱动，容器释放后再碰它就来不及了。
  /// 3. **解除拦截在关窗之前**——`close()` 发的是 `WM_SYSCOMMAND/SC_CLOSE`，
  ///    `window_manager` 的 WM_CLOSE 处理器在 `preventClose` 为真时直接 `return -1`
  ///    （`window_manager_plugin.cpp:321-325`），不先关掉拦截窗口是关不掉的。
  Future<void> quit() async {
    if (_quitting) return;
    debugPrint('[AppLifecycle] 收到退出信号，开始执行退出流程');
    _quitting = true;

    // 1. 摘掉托盘图标与菜单句柄：留着会在任务栏留下幽灵图标
    await _releaseTray();
    // 2. 停播并释放系统媒体会话（SMTC）：必须在容器释放之前
    await _releaseAudio();
    // 3. 释放 Provider 容器：触发各长生命周期服务的 onDispose
    _releaseContainer();
    // 4. 解除关闭拦截，5. 关窗口（走正常关闭序列，不用 destroy()）
    await _allowClose();
    await _closeWindow();
  }

  Future<void> _releaseTray() async {
    try {
      await DesktopTray.instance.dispose();
    } catch (error) {
      debugPrint('[AppLifecycle] 释放托盘失败：$error');
    }
  }

  /// 停播 → 显式释放插件侧静态 WinRT 状态 → 留一点时间让平台通道落地。
  ///
  /// `audio_service_win 0.0.3` 把 `smtc` / `updater` / `mediaPlayer` 放在文件级 static 里，
  /// 只靠静态析构会在 COM/WinRT 已经拆掉之后才释放，实测必崩（`ntdll + 0xc000000d`，根因见
  /// <https://github.com/HemantKArya/audio_service_win/issues/5>）。
  /// 现用的 fork 在插件析构里补了同一套释放，
  /// 所以这里是「在 COM 还活着时确定性地放掉」的保险，而不是唯一生路；
  /// 插件侧对 `smtc` 为空的状态更新有判空，晚到的 `updateState` 不会踩空。
  Future<void> _releaseAudio() async {
    final handler = _audioHandler;
    _audioHandler = null;

    if (handler != null) {
      try {
        await handler.stop();
      } catch (error) {
        debugPrint('[AppLifecycle] 停止音频服务失败：$error');
      }
    }

    // 只有 Windows 实现有这个方法，按运行时类型判断（其余平台 instance 不是它）。
    // 按理来说 stop 就行，应该保险起见还是调一次 shutdown
    final platform = AudioServicePlatform.instance;
    if (platform is AudioServiceWin) {
      try {
        await platform.shutdown();
      } catch (error) {
        debugPrint('[AppLifecycle] 释放 SMTC 失败：$error');
      }
    }

    // `handler.stop()` 只把 playbackState 置为 idle，真正的平台调用
    // （stopService → updateState(2)：媒体卡片置 Stopped 并 disable）是 audio_service
    // 观察到状态流后异步发的，await 不等它。留一个宽限期，免得进程被紧接着的关闭带走。
    await Future<void>.delayed(_audioTeardownGrace);
  }

  /// 退出时留给音频服务把 `updateState(2)` 送到原生侧的时间（见 [_releaseAudio]）。
  static const Duration _audioTeardownGrace = Duration(milliseconds: 200);

  void _releaseContainer() {
    final container = _container;
    _container = null;
    try {
      container?.dispose();
    } catch (error) {
      debugPrint('[AppLifecycle] 释放 Provider 容器失败：$error');
    }
  }

  /// 关掉关闭拦截：解除后 `WM_CLOSE` 才会落到 `DefWindowProc` 走正常关闭序列。
  Future<void> _allowClose() async {
    try {
      await windowManager.setPreventClose(false);
    } catch (error) {
      debugPrint('[AppLifecycle] 解除关闭拦截失败：$error');
    }
  }

  /// 关窗口：用 `close()` 而不是 `destroy()`。
  ///
  /// `destroy()` 是 `PostQuitMessage(0)`（`window_manager.cpp:233`），只往线程消息队列
  /// 投一条 `WM_QUIT`，`WM_DESTROY → Win32Window::Destroy() → FlutterWindow::OnDestroy()`
  /// 这条引擎析构路径根本不走，窗口/插件注册/纹理都在「没析构」的状态下被进程退出带走。
  /// `close()` 发 `SC_CLOSE`，正常关闭序列跑完，插件析构（含 SMTC 释放）也才有机会执行。
  Future<void> _closeWindow() async {
    try {
      await windowManager.close();
    } catch (error) {
      debugPrint('[AppLifecycle] 关闭窗口失败：$error');
    }
  }
}
