import 'dart:ffi';
import 'dart:io';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:ffi/ffi.dart';

/// 播放器状态快照(由 [MpvPlayer.pollState] 轮询采集)。
final class MpvState {
  const MpvState({
    this.position = 0,
    this.duration = 0,
    this.paused = false,
    this.ended = false,
    this.volume = 80,
  });

  final double position;
  final double duration;
  final bool paused;
  final bool ended;
  final double volume;

  MpvState copyWith({
    double? position,
    double? duration,
    bool? paused,
    bool? ended,
    double? volume,
  }) =>
      MpvState(
        position: position ?? this.position,
        duration: duration ?? this.duration,
        paused: paused ?? this.paused,
        ended: ended ?? this.ended,
        volume: volume ?? this.volume,
      );
}

/// 纯 Dart 的 libmpv FFI 封装(Windows,spike 用)。
///
/// App 的 just_audio 依赖 Flutter 平台通道,纯 Dart 进程里跑不了;
/// 这里直接 FFI 驱动 media_kit_libs_windows_audio 附带的 libmpv-2.dll,
/// 不需要用户安装 mpv.exe。轮询属性而非注册回调,避免事件结构体解析。
class MpvPlayer {
  bool _ready = false;
  late final Pointer<Void> _ctx;
  late final DynamicLibrary _lib;

  late final Pointer<Void> Function() _mpvCreate;
  late final int Function(Pointer<Void>) _mpvInitialize;
  late final int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) _mpvCommand;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
      _mpvSetPropertyString;
  late final int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Void>)
      _mpvSetProperty;
  late final int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Void>)
      _mpvGetProperty;
  late final void Function(Pointer<Void>) _mpvTerminateDestroy;

  static const int _formatFlag = 3; // MPV_FORMAT_FLAG
  static const int _formatDouble = 5; // MPV_FORMAT_DOUBLE

  bool get isReady => _ready;

  /// 加载 DLL 并初始化 mpv 核心。libmpv-2.dll 依次查找
  /// 构建产物目录,依赖 DLL 由 SetDllDirectoryW 保证可解析。
  void load({bool nullAudio = false}) {
    final dir = _locateDllDir();
    // SetDllDirectoryW 需要绝对路径,否则依赖 DLL(avcodec 等)解析失败(error 126)
    final absDir = Directory(dir).absolute.path;

    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setDllDirectory = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('SetDllDirectoryW');
    final dirPtr = absDir.toNativeUtf16();
    setDllDirectory(dirPtr);
    calloc.free(dirPtr);

    _lib = DynamicLibrary.open('$absDir\\libmpv-2.dll');
    _mpvCreate = _lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'mpv_create');
    _mpvInitialize = _lib
        .lookupFunction<Int32 Function(Pointer<Void>), int Function(
            Pointer<Void>)>('mpv_initialize');
    _mpvCommand = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
        int Function(
            Pointer<Void>, Pointer<Pointer<Utf8>>)>('mpv_command');
    _mpvSetPropertyString = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>,
            Pointer<Utf8>)>('mpv_set_property_string');
    _mpvSetProperty = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Void>),
        int Function(
            Pointer<Void>, Pointer<Utf8>, int, Pointer<Void>)>('mpv_set_property');
    _mpvGetProperty = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Utf8>, int,
            Pointer<Void>)>('mpv_get_property');
    _mpvTerminateDestroy = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('mpv_terminate_destroy');

    _ctx = _mpvCreate();
    if (_ctx == nullptr) {
      throw StateError('mpv_create 失败');
    }

    _opt('terminal', 'no');
    _opt('vo', 'null'); // 纯音频,无视频渲染
    _opt('audio-display', 'no');
    _opt('user-agent', NetworkConfig.userAgent);
    _opt('referrer', 'https://www.bilibili.com');
    _opt('network-timeout', '15');
    if (nullAudio) {
      _opt('ao', 'null'); // probe 模式:解码但不出声
    }

    final rc = _mpvInitialize(_ctx);
    if (rc != 0) {
      throw StateError('mpv_initialize 失败 (rc=$rc)');
    }
    _ready = true;
  }

  static String _locateDllDir() {
    final candidates = <String>[
      ?Platform.environment['BILIMUSIC_MPV_DIR'],
      'build\\windows\\x64\\libmpv',
      'build\\windows\\x64\\runner\\Release',
      'build\\windows\\x64\\runner\\Debug',
    ];
    for (final dir in candidates) {
      if (File('$dir\\libmpv-2.dll').existsSync()) return dir;
    }
    throw StateError(
      '未找到 libmpv-2.dll:请先执行 flutter build windows,'
      '或将 BILIMUSIC_MPV_DIR 指向包含该 DLL 的目录',
    );
  }

  void _opt(String name, String value) => _setString(name, value);

  void play(String url) {
    _command(['loadfile', url]);
    _setFlag('pause', false);
  }

  void pause(bool value) => _setFlag('pause', value);

  void seekRelative(double seconds) =>
      _command(['seek', '$seconds', 'relative']);

  void seekAbsolute(double seconds) =>
      _command(['seek', '$seconds', 'absolute']);

  void bumpVolume(double delta) {
    final current = _getDouble('volume');
    if (current.isNaN) return;
    _setString('volume', (current + delta).clamp(0, 130).toStringAsFixed(0));
  }

  MpvState pollState() {
    final pos = _getDouble('time-pos');
    final dur = _getDouble('duration');
    final vol = _getDouble('volume');
    return MpvState(
      position: pos.isNaN ? 0 : pos,
      duration: dur.isNaN ? 0 : dur,
      paused: _getFlag('pause'),
      ended: _getFlag('eof-reached'),
      volume: vol.isNaN ? 80 : vol,
    );
  }

  void dispose() {
    if (!_ready) return;
    _command(['stop']);
    _mpvTerminateDestroy(_ctx);
    _ready = false;
  }

  // ── 底层封装 ─────────────────────────────────────────────────────────────

  int _command(List<String> args) {
    final array = calloc<Pointer<Utf8>>(args.length + 1);
    final allocated = <Pointer<Utf8>>[];
    for (var i = 0; i < args.length; i++) {
      final p = args[i].toNativeUtf8();
      allocated.add(p);
      array[i] = p;
    }
    array[args.length] = nullptr;
    final rc = _mpvCommand(_ctx, array);
    for (final p in allocated) {
      calloc.free(p);
    }
    calloc.free(array);
    return rc;
  }

  void _setString(String name, String value) {
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    _mpvSetPropertyString(_ctx, namePtr, valuePtr);
    calloc.free(namePtr);
    calloc.free(valuePtr);
  }

  void _setFlag(String name, bool value) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<Int32>();
    out.value = value ? 1 : 0;
    _mpvSetProperty(_ctx, namePtr, _formatFlag, out.cast<Void>());
    calloc.free(namePtr);
    calloc.free(out);
  }

  bool _getFlag(String name) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<Int32>();
    final rc = _mpvGetProperty(_ctx, namePtr, _formatFlag, out.cast<Void>());
    final value = rc == 0 && out.value != 0;
    calloc.free(namePtr);
    calloc.free(out);
    return value;
  }

  double _getDouble(String name) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<Double>();
    final rc = _mpvGetProperty(_ctx, namePtr, _formatDouble, out.cast<Void>());
    final value = out.value;
    calloc.free(namePtr);
    calloc.free(out);
    return rc == 0 ? value : double.nan;
  }
}
