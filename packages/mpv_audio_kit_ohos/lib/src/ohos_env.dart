import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// HAP 里 libmpv 的默认 soname。
///
/// 打进 HAP 的 `libs/<abi>/*.so` 由系统 linker 按 soname 解析，
/// 不需要也不应该拼绝对路径（bundle 的 codePath 随安装位置变化）。
const String kDefaultLibmpvName = 'libmpv.so';

/// musl 与 glibc 的 `LC_NUMERIC` 都是 1。
const int _lcNumeric = 1;

/// 当前进程是否跑在 OpenHarmony / HarmonyOS 上。
///
/// 不用 `Platform.isOhos`：普通 Flutter SDK 的 dart:io 没有这个字段，
/// 字符串判断让同一份代码在其它平台也能编译。
bool get isOhosPlatform => Platform.operatingSystem == 'ohos';

/// HAP 里 `libs/` 下的 ABI 目录名。
///
/// Dart VM 在 OHOS 上仍是 linux 系 ABI，`Abi.current()` 会给出
/// `linuxX64` / `linuxArm64`。
String get ohosAbi {
  // OHOS 版 SDK 的 Abi 是 `ohos_x64` / `ohos_arm64` / `ohos_arm`；官方 SDK
  // 没有 `Abi.ohosX64` 这类常量，所以按字符串映射，保证同一份代码在两套
  // SDK 下都能编译。
  final current = '${Abi.current()}';
  switch (current) {
    case 'ohos_x64':
    case 'linux_x64':
      return 'x86_64';
    case 'ohos_arm64':
    case 'linux_arm64':
      return 'arm64-v8a';
    case 'ohos_arm':
    case 'linux_arm':
      return 'armeabi-v7a';
    default:
      return current;
  }
}

/// 包内默认日志出口：走 Dart 的 stdout，在 OHOS 上由 Flutter 引擎转进 hilog。
void defaultLog(String message) => print('[mpv_audio_kit_ohos] $message');

typedef _SetLocaleNative = Pointer<Utf8> Function(Int32, Pointer<Utf8>);
typedef _SetLocaleDart = Pointer<Utf8> Function(int, Pointer<Utf8>);

/// 把进程的 `LC_NUMERIC` 修成 `C`，返回是否确认生效。
///
/// libmpv 的 API 契约（`mpv/client.h`）要求调用方把这一项设为 C，
/// 否则 `mpv_create()` 会直接 `abort()`。mpv 自己起的线程继承进程级
/// locale，所以必须进程级设置，不能只给当前线程设。
///
/// 失败只记录不抛：locale 本来就是 C 时（多数应用进程）mpv 仍能起来。
bool applyCNumericLocale({void Function(String message)? log}) {
  final logger = log ?? defaultLog;
  final setlocale = _lookupSetLocale(logger);
  if (setlocale == null) {
    return false;
  }

  try {
    final result = using(
      (arena) => setlocale(_lcNumeric, 'C'.toNativeUtf8(allocator: arena)),
    );
    if (result == nullptr) {
      logger('setlocale(LC_NUMERIC, "C") 返回空指针');
      return false;
    }
    final current = result.toDartString();
    if (current != 'C') {
      logger('setlocale(LC_NUMERIC, "C") 实际得到 "$current"');
      return false;
    }
    return true;
  } catch (error) {
    logger('setlocale 调用失败：$error');
    return false;
  }
}

_SetLocaleDart? _lookupSetLocale(void Function(String message) log) {
  final sources = <(String, DynamicLibrary Function())>[
    ('libc.so', () => DynamicLibrary.open('libc.so')),
    ('process', DynamicLibrary.process),
  ];
  for (final (label, open) in sources) {
    try {
      final lib = open();
      return lib.lookupFunction<_SetLocaleNative, _SetLocaleDart>('setlocale');
    } catch (error) {
      log('setlocale：$label 取不到符号（$error）');
    }
  }
  return null;
}
