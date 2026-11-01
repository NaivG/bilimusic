/// OpenHarmony / HarmonyOS 上运行 `mpv_audio_kit` 的引导层。
///
/// `mpv_audio_kit` 是纯 FFI 包（Android / iOS / Linux / macOS / Windows 的
/// 差异全在 Dart 侧），OHOS 上缺的只有两件事：
///
/// 1. `libmpv.so` 的定位与加载——上游的 `_resolvePath()` 没有 ohos 分支；
/// 2. 进程级 `setlocale(LC_NUMERIC, "C")`——libmpv 的 API 契约，否则
///    `mpv_create()` 直接 abort。
///
/// 这里不重复声明任何 mpv 符号，也不经过 ArkTS / napi：Dart VM 自己
/// `dlopen` HAP 里的 `libs/<abi>/libmpv.so`，与其它平台同一条 FFI 路径。
library;

import 'dart:io';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;

import 'src/ohos_env.dart';
import 'src/probe.dart';

export 'src/probe.dart' show MpvNativeProbe, MpvProbeException;

/// [MpvAudioKitOhos.ensureInitialized] 的结果。
class MpvOhosBootResult {
  const MpvOhosBootResult({
    required this.ready,
    required this.platform,
    required this.libraryPath,
    this.localeApplied = false,
    this.clientApiVersion,
    this.mpvVersion,
    this.error,
  });

  /// libmpv 是否可用（false 时应用应退回占位播放器）。
  final bool ready;

  /// `Platform.operatingSystem`，非 OHOS 平台也会原样记录。
  final String platform;

  /// 实际交给 `DynamicLibrary.open` 的路径 / soname。
  final String libraryPath;

  /// `setlocale(LC_NUMERIC, "C")` 是否确认生效。
  final bool localeApplied;

  /// `mpv_client_api_version()` 原始值；没走到自检时为 null。
  final int? clientApiVersion;

  /// 深度自检读到的 `mpv-version`。
  final String? mpvVersion;

  final String? error;

  String? get apiVersionText {
    final version = clientApiVersion;
    if (version == null) return null;
    return '${version >> 16}.${version & 0xffff}';
  }

  String get summary {
    if (ready) {
      final api = apiVersionText;
      final mpv = mpvVersion;
      return 'libmpv 已就绪（$libraryPath'
          '${api == null ? '' : '，api $api'}'
          '${mpv == null ? '' : '，mpv $mpv'}'
          '，abi $ohosAbi，locale ${localeApplied ? 'C' : '未修正'}）';
    }
    return 'libmpv 不可用（$libraryPath）：${error ?? '未知错误'}';
  }
}

/// OHOS 上的 libmpv 引导入口。
abstract final class MpvAudioKitOhos {
  static MpvOhosBootResult? _result;

  /// 是否运行在 OHOS 上。
  static bool get isOhos => isOhosPlatform;

  /// 最近一次 [ensureInitialized] 的结果；未调用过为 null。
  static MpvOhosBootResult? get result => _result;

  /// libmpv 是否已就绪。
  static bool get isReady => _result?.ready ?? false;

  /// 初始化 libmpv，幂等。
  ///
  /// [libmpv] 默认取 HAP 里的 soname `libmpv.so`；只有要指定别的二进制时
  /// 才传绝对路径。非 OHOS 平台会直接转给 `mpv_audio_kit`，方便调用方
  /// 在自己的启动分支里统一写一行。
  ///
  /// [deepProbe] 为 true 时会真的 `mpv_initialize()` 一次再销毁：能提前
  /// 暴露 OHAudio / native_media 依赖缺失的问题，代价是多一次 core 冷启动。
  static MpvOhosBootResult ensureInitialized({
    String? libmpv,
    bool hotRestartCleanup = true,
    bool deepProbe = true,
    void Function(String message)? logger,
  }) {
    final cached = _result;
    if (cached != null) {
      return cached;
    }

    final log = logger ?? defaultLog;
    final path = libmpv ?? kDefaultLibmpvName;

    if (!isOhosPlatform) {
      MpvAudioKit.ensureInitialized(
        libmpv: libmpv,
        hotRestartCleanup: hotRestartCleanup,
      );
      log('非 OHOS 平台（${Platform.operatingSystem}），交给 mpv_audio_kit 默认路径');
      return _result = MpvOhosBootResult(
        ready: true,
        platform: Platform.operatingSystem,
        libraryPath: path,
      );
    }

    final localeApplied = applyCNumericLocale(log: log);
    try {
      final probe = probeLibmpv(path, deep: deepProbe);
      MpvAudioKit.ensureInitialized(
        libmpv: path,
        hotRestartCleanup: hotRestartCleanup,
      );
      final result = MpvOhosBootResult(
        ready: true,
        platform: Platform.operatingSystem,
        libraryPath: path,
        localeApplied: localeApplied,
        clientApiVersion: probe.clientApiVersion,
        mpvVersion: probe.mpvVersion,
      );
      log(result.summary);
      return _result = result;
    } catch (error, stack) {
      final result = MpvOhosBootResult(
        ready: false,
        platform: Platform.operatingSystem,
        libraryPath: path,
        localeApplied: localeApplied,
        error: '$error',
      );
      log('${result.summary}\n$stack');
      return _result = result;
    }
  }

  /// 直接对 libmpv 做一次自检，不改变 [ensureInitialized] 的缓存状态。
  ///
  /// 诊断页用：可以在播放器已经在跑的时候再验一次库与 core。
  static MpvNativeProbe probe({String? libmpv, bool deep = true}) =>
      probeLibmpv(libmpv ?? kDefaultLibmpvName, deep: deep);
}
