# OpenHarmony / HarmonyOS 端（`ohos/`）

本目录是 `flutter create --platforms ohos` 生成的 OpenHarmony 宿主工程，配套一套把
「[三方库适配表](https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md)
里已适配的库」接进来的依赖接线。

## 构建

前置：DevEco Studio 26（含 API 26 SDK / hvigor / ohpm）+ OHOS 版 Flutter SDK
（默认 `D:\flutter_flutter`，可用 `FLUTTER_SDK` 覆盖）。

```powershell
.\tool\ohos_build.ps1                                   # 模拟器 x64 debug
.\tool\ohos_build.ps1 -TargetPlatform ohos-arm64        # 真机
.\tool\ohos_build.ps1 -TargetPlatform ohos-arm64 -Release
```

产物：`build\ohos\hap\entry-default-signed.hap`。

装到设备/模拟器：

```powershell
hdc tconn 127.0.0.1:5555
hdc install -r build\ohos\hap\entry-default-signed.hap
hdc shell aa start -a EntryAbility -b github.naivg.bilimusic
```

### 脚本里三个非默认变量的原因

`tool/ohos_build.ps1` 会强制设置这三项，不要绕开：

| 变量 | 为什么 |
| --- | --- |
| `PUB_CACHE` = SDK 内缓存（同在 D 盘） | flutter_tools 给 hvigor 写 `modules[].srcPath` 用的是 `path.relative()`；pub 缓存在 C: 盘、工程在 D: 盘时只能退回绝对路径，hvigor 直接 `The srcPath is not a relative path` 失败 |
| `GIT_LFS_SKIP_SMUDGE=1` | git 依赖里若带 Git LFS 大文件，gitcode 的 LFS 端点不给匿名下载，`git lfs` 拉失败会让整个 `pub get` 挂掉；pub 只需要源码树，所以留着当护栏 |
| `.dart_tool/package_config.json` 构建期只读 | DevEco / 其它 IDE 的 Flutter 分析服务会用**官方** Flutter SDK 覆盖它，HAP 启动时报 `Unknown platform.`（官方 SDK 没有 OHOS 的 `defaultTargetPlatform`） |

### 签名

`ohos/build-profile.json5` 里是 DevEco 自动签名写进去的**证书绝对路径 + 加密口令**，
属于本机材料，已被 `.gitignore` 排除。全新检出时脚本会从
`build-profile.json5.example` 补一份，但签名仍需在 DevEco 里
`File > Project Structure > Signing Configs` 勾选自动签名，否则出不了可安装的 HAP。

## 三方库接线

两种接法，原则是**能用独立平台实现包就不用 `dependency_overrides`**——那样其它平台的
版本与行为完全不变。

### 1. 独立平台实现包（`*_ohos`，`implements:` + `platforms: ohos:`）

front-end 包保持 pub.dev 版本，另加一个只声明 `ohos` 平台、用 `implements:` 指向
front-end 的实现包。flutter_tools 会自动选中它。

| 库 | 上游 | 平台实现 | 来源 |
| --- | --- | --- | --- |
| `shared_preferences` | ^2.5.3 | `shared_preferences_ohos` 2.2.0 | pub.dev（openharmony-tpc） |
| `path_provider` | ^2.1.5 | `path_provider_ohos` 2.2.1 | pub.dev（openharmony-tpc） |
| `url_launcher` | ^6.3.2 | `url_launcher_ohos` 6.3.0 | pub.dev（openharmony-tpc） |
| `permission_handler` | 11.4.0 | `permission_handler_ohos` 12.0.1 | `flutter_permission_handler` @ `12.0.1-ohos-1.0.0` |
| `sqflite` | 2.4.x | `sqflite_ohos` 2.4.2 | `flutter_sqflite` @ `2.4.2-ohos-1.0.0` |
| `audio_service` | ^0.18.18 | `audio_service_ohos` | `packages/audio_service_ohos`（本仓库） |
| `share_plus` | ^12.0.2 | `share_plus_ohos` | `packages/share_plus_ohos`（本仓库） |

### 2. `dependency_overrides`（只剩一条）

`audio_session` 没有平台接口层，做不成 `platforms: ohos` 的实现包；而 `audio_service`
自己也依赖它，pub 不允许「root 用 path、别人用 hosted」这种来源不一致，所以只能整包
vendored 到 `packages/audio_session` 并用 path override。

| 库 | 覆盖到 | 来源 |
| --- | --- | --- |
| `audio_session` | 0.2.2 | `packages/audio_session`（path，基于上游 0.2.2 + `ohos/`） |

TAG 约定 `x.y.z-ohos-1.0.0`（`x.y.z` 是该适配基于的上游版本）只对还剩的 git 依赖有意义。

### 三个例外

- **`file_picker` 整包改名**：适配仓库把包名改成了 `file_picker_ohos`（入口
  `lib/file_picker_ohos.dart`），不是独立平台实现包，所以直接替换依赖并对齐了 4 处
  import。它自带全平台实现，其它平台的 picker 行为与原包一致。
- **`audio_session` 只能 vendored**：见上。它的 Dart 代码被改过（公共 API 加了
  `ohosAudioAttributes` 等），改的是**所有平台都会编译**的文件，所以平台判定一律用
  `Platform.operatingSystem == 'ohos'`，绝不能用只有鸿蒙 SDK 才有的
  `TargetPlatform.ohos` / `Platform.isOhos`，否则官方 SDK 下直接编译失败。
- **`mpv_audio_kit` 不是联邦化插件**：它是纯 FFI，没有平台接口层，OHOS 引导放在
  `packages/mpv_audio_kit_ohos`（path 依赖），只补 libmpv 定位与
  `setlocale(LC_NUMERIC, "C")`。

### 3. 本仓库自己的引导包（`packages/mpv_audio_kit_ohos`）

`mpv_audio_kit` 不是联邦化插件（没有 platform interface），所以没法用 `*_ohos`
实现包补平台；但它本身是纯 FFI，只缺「libmpv 怎么找」与「locale 必须是 C」两件。
这两件事由 `packages/mpv_audio_kit_ohos` 在 Dart 侧补，`pubspec.yaml` 用 path
依赖接进来；其它平台的解析与行为不变。

## 原生侧改动

- `entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets` 由 flutter_tools 生成
  （已 gitignore），当前注册 9 个 OHOS 插件。
- `entry/src/main/module.json5`：`ohos.permission.INTERNET` +
  `ohos.permission.KEEP_BACKGROUND_RUNNING`，并在 `EntryAbility` 上声明
  `backgroundModes: ["audioPlayback"]`（注意它是 **ability 级**字段，写到 module 级
  hvigor 会报 `property name must be valid`）。这是 `audio_service` 的 OHOS 实现用
  AVSession 承接媒体会话、退后台不断播的前提。
- `lib/main.dart` 的 OHOS 分支：先 `runApp` 一个不依赖任何插件的启动壳
  （`lib/app/ohos/ohos_boot_screen.dart`），再把真正的 App 顶上去；初始化抛错会留在
  启动壳上并显示原因，避免白屏。libmpv 不再跳过，改由
  `MpvAudioKitOhos.ensureInitialized()` 引导（自检失败才退回占位播放器）。

## 还没接的库

| 库 | 影响 |
| --- | --- |
| `bonsoir` | mDNS 发现，无 OHOS 实现 → 局域网同步不可用 |
| `gt3_flutter_plugin` | 极验验证码，无 OHOS 实现 → 密码登录过不了验证码，请用扫码登录 |
| `sqflite_common_ffi` / `window_manager` / `tray_manager` / `super_context_menu` / `screen_retriever` / `restart_app` / `audio_service_win` / `audio_service_mpris` / `jni` | 桌面 / Android 专属，OHOS 分支本来就不走 |
