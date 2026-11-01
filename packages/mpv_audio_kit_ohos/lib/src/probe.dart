import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ohos_env.dart';

/// libmpv 的启动自检结果：只证明「库能打开、core 能建起来」，
/// 不装载媒体、不建事件循环、不碰音频设备。
class MpvNativeProbe {
  const MpvNativeProbe({
    required this.libraryPath,
    required this.clientApiVersion,
    this.mpvVersion,
    this.coreCreated = true,
  });

  final String libraryPath;

  /// `mpv_client_api_version()` 的原始值：高 16 位主版本，低 16 位次版本。
  final int clientApiVersion;

  /// 深度自检时 `mpv-version` 属性的值；浅自检或属性不可读时为 null。
  final String? mpvVersion;

  final bool coreCreated;

  String get apiVersionText =>
      '${clientApiVersion >> 16}.${clientApiVersion & 0xffff}';

  @override
  String toString() => 'MpvNativeProbe($libraryPath, api $apiVersionText'
      '${mpvVersion == null ? '' : ', mpv $mpvVersion'})';
}

/// 自检失败。消息里带上 ABI 与库路径，设备上没有调试器时靠它定位。
class MpvProbeException implements Exception {
  const MpvProbeException(this.message);

  final String message;

  @override
  String toString() => 'MpvProbeException: $message';
}

/// 深度自检时用到的、不会改变播放行为的选项。
const Map<String, String> _probeOptions = {
  'vo': 'null',
  'vid': 'no',
  'audio-display': 'no',
  'idle': 'yes',
  'config': 'no',
  'terminal': 'no',
  'load-scripts': 'no',
  'input-default-bindings': 'no',
  'msg-level': 'all=warn',
  'audio-client-name': 'mpv_audio_kit_ohos_probe',
};

typedef _ApiVersionNative = UnsignedLong Function();
typedef _ApiVersionDart = int Function();
typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _InitNative = Int32 Function(Pointer<Void>);
typedef _InitDart = int Function(Pointer<Void>);
typedef _TerminateNative = Void Function(Pointer<Void>);
typedef _TerminateDart = void Function(Pointer<Void>);
typedef _SetOptionNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _SetOptionDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetStringNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _GetStringDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _ErrorStringNative = Pointer<Utf8> Function(Int32);
typedef _ErrorStringDart = Pointer<Utf8> Function(int);

/// 打开 libmpv 并做一次最小自检。
///
/// [deep] 为 true 时还会 `mpv_initialize()` 一次再销毁，验证 core 与
/// 依赖链（OHAudio / native_media）在应用进程里真的能起来；为 false
/// 时只建句柄再销毁，够用来确认库与符号都在。
MpvNativeProbe probeLibmpv(String path, {bool deep = true}) {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(path);
  } catch (error) {
    throw MpvProbeException(
      '打不开 $path（ohos $ohosAbi）：$error\n'
      '确认 HAP 里有 libs/$ohosAbi/libmpv.so，且它的 DT_NEEDED 都能解析'
      '（最常见的是缺同目录的 libc++_shared.so）。',
    );
  }

  final apiVersion = lib.lookupFunction<_ApiVersionNative, _ApiVersionDart>(
    'mpv_client_api_version',
  )();
  final create = lib.lookupFunction<_CreateNative, _CreateDart>('mpv_create');
  final terminate = lib.lookupFunction<_TerminateNative, _TerminateDart>(
    'mpv_terminate_destroy',
  );

  final handle = create();
  if (handle == nullptr) {
    throw const MpvProbeException('mpv_create() 返回空句柄（locale 不是 C？）');
  }

  String? mpvVersion;
  try {
    if (deep) {
      _applyProbeOptions(lib, handle);
      final initialize = lib.lookupFunction<_InitNative, _InitDart>(
        'mpv_initialize',
      );
      final rc = initialize(handle);
      if (rc < 0) {
        throw MpvProbeException(
          'mpv_initialize 失败：${_errorString(lib, rc)}（$rc）',
        );
      }
      mpvVersion = _getString(lib, handle, 'mpv-version');
    }
  } finally {
    terminate(handle);
  }

  return MpvNativeProbe(
    libraryPath: path,
    clientApiVersion: apiVersion,
    mpvVersion: mpvVersion,
  );
}

void _applyProbeOptions(DynamicLibrary lib, Pointer<Void> handle) {
  final setOption = lib.lookupFunction<_SetOptionNative, _SetOptionDart>(
    'mpv_set_option_string',
  );
  for (final entry in _probeOptions.entries) {
    final rc = using(
      (arena) => setOption(
        handle,
        entry.key.toNativeUtf8(allocator: arena),
        entry.value.toNativeUtf8(allocator: arena),
      ),
    );
    if (rc < 0) {
      throw MpvProbeException(
        'mpv_set_option_string(${entry.key}) 失败：${_errorString(lib, rc)}（$rc）',
      );
    }
  }
}

String? _getString(DynamicLibrary lib, Pointer<Void> handle, String name) {
  final getProperty = lib.lookupFunction<_GetStringNative, _GetStringDart>(
    'mpv_get_property_string',
  );
  final free = lib.lookupFunction<_FreeNative, _FreeDart>('mpv_free');

  final value = using(
    (arena) => getProperty(handle, name.toNativeUtf8(allocator: arena)),
  );
  if (value == nullptr) {
    return null;
  }
  try {
    return value.toDartString();
  } finally {
    free(value.cast());
  }
}

String _errorString(DynamicLibrary lib, int error) {
  try {
    final fn = lib.lookupFunction<_ErrorStringNative, _ErrorStringDart>(
      'mpv_error_string',
    );
    return fn(error).toDartString();
  } catch (_) {
    return 'mpv_error_string 不可用';
  }
}
