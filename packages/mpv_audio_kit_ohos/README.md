# mpv_audio_kit_ohos

OpenHarmony / HarmonyOS 上运行 [`mpv_audio_kit`](https://pub.dev/packages/mpv_audio_kit)
的引导层。

## 补了什么

| 缺口 | 这里怎么补 |
| --- | --- |
| `mpv_audio_kit` 的 `_resolvePath()` 没有 `ohos` 分支，`ensureInitialized()` 会抛 `Platform not supported: ohos` | 显式传 `libmpv: 'libmpv.so'`（HAP 里 `libs/<abi>/libmpv.so` 的 soname，由系统 linker 解析），再调上游的 `MpvAudioKit.ensureInitialized(libmpv: …)` |
| libmpv 的 API 契约要求 `setlocale(LC_NUMERIC, "C")`，上游只对 Linux / macOS / iOS 做 | 通过 `dlopen("libc.so")` 调 `setlocale(LC_NUMERIC=1, "C")`，并回读确认返回值是 `C` |
| 加载失败要等到事件 isolate 里才炸，设备上没有可读堆栈 | 启动阶段先 `dlopen` + `mpv_create`（可选 `mpv_initialize`）自检一次，失败返回 `MpvOhosBootResult.error`，不抛给启动路径 |

上游的 `_applyPlatformQuirks()` 在 OHOS 上会尝试 `libSystem.B.dylib` 并吞掉异常，
不影响使用；真正的 locale 修正由本包在调用上游之前完成。

## 用法

```dart
import 'package:mpv_audio_kit_ohos/mpv_audio_kit_ohos.dart';

// 放在 ProviderContainer / Player 创建之前。
final boot = MpvAudioKitOhos.ensureInitialized();
if (!boot.ready) {
  // 退回占位播放器，UI 照常启动
  debugPrint(boot.summary);
}
```

`ensureInitialized()` 幂等；非 OHOS 平台会原样转给 `mpv_audio_kit`。

## `libmpv.so` 从哪来

由仓库根目录的 `tool/ohos_libmpv/` 交叉编译，`ao_ohaudio`、音频专用（`WITH_VIDEO=0`）。

```powershell
.\tool\build_libmpv_ohos.ps1                     # x86_64（模拟器）
.\tool\build_libmpv_ohos.ps1 -Arch aarch64       # 真机
```

产物 `D:\ohos-libmpv\<arch>-build\libmpv.so` 拷到对应 ABI 目录：

```text
ohos/entry/libs/x86_64/libmpv.so      # 模拟器
ohos/entry/libs/arm64-v8a/libmpv.so   # 真机
```

`.so` 不进仓库。hvigor 会把`entry/libs/<abi>/*.so` 原样打进 HAP，
运行时由 linker 从应用沙箱的`/data/storage/el1/bundle/libs/<abi>/`
（安装态在`/data/app/el1/bundle/public/<bundle>/libs/<abi>/`）按 soname 找到。

`libmpv.so` 的 `DT_NEEDED` 只有系统库：`libc.so`、`libc++_shared.so`、
`libohaudio.so`、`libnative_window.so`、`libnative_image.so`、
`libnative_media_{codecbase,core,vdec,acodec}.so`。

## 验证

设备上（模拟器 / 真机）看 hilog 里 `mpv_audio_kit_ohos` 前缀：

```text
[mpv_audio_kit_ohos] libmpv 已就绪（libmpv.so，api 2.5，mpv mpv v0.41.0-dev-g6edeee00a，abi x86_64，locale C）
```

失败时该行会带上 `MpvProbeException` 的具体原因（打不开 / 依赖缺失 /
`mpv_initialize` 返回码）。第一次接线时踩到的坑是 `libc++_shared.so`：它不在应用的
linker namespace 里，必须在同目录带一份（`tool/ohos_build.ps1` 会自动从 NDK 拷贝）。
