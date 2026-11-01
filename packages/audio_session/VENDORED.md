# `audio_session`（vendored）

这是 [audio_session](https://pub.dev/packages/audio_session) 0.2.2 的**整包副本**，
只为补一份 OpenHarmony 平台实现。上游发布在 pub.dev，这里不从上游仓库直接引用。

## 为什么不能做成「独立平台实现包」

`audio_session` **不是联邦化插件**：没有 `audio_session_platform_interface`，四个方法
通道全部内联在 front-end 的 Dart 代码里，`_androidAudioManager` / `_avAudioSession` /
`_ohosAudionManager` 也是 front-end 自己 `new` 的。更要紧的是鸿蒙适配**扩展了公共
API**：

- `AudioSessionConfiguration.ohosAudioAttributes`
- `setActive()` 新增 `ohosAudioAttributes` / `ohosAudioConcurrencyMode` 具名参数
- `activate()` 里新增一整条 `else if` 分支

这些都得改在 front-end 的类上，外部包补不了，所以只能整包 vendored。

## 为什么仍然用 `dependency_overrides`

`audio_service` 自己也依赖 `audio_session`。pub 对同一个包只允许存在一个 source，
root 用 `path:`、别人用 hosted 会直接版本求解失败（`audio_session from hosted is
required`）。所以它的 path 依赖只能写在 `dependency_overrides` 里。

好处是这条 override 纯 path：不联网、不过 git、不碰 LFS（上游仓库的 `example/`
里有 10 MB 的 LFS 文件，vendor 时已整棵裁掉）。

## 相对上游 0.2.2 的改动

1. 新增 `lib/src/ohos.dart`（`OhosAudioManager`）+ `lib/audio_session.dart` 里多一行
   `export 'src/ohos.dart';`
2. `lib/src/core.dart` 补鸿蒙分支与公共 API（见上）。
3. **平台判定改写成 `Platform.operatingSystem == 'ohos'`**。

第 3 条是关键：适配分支原本写的是 `defaultTargetPlatform == TargetPlatform.ohos`，
而 `TargetPlatform.ohos` 只存在于鸿蒙版 Flutter SDK 的枚举里。官方 Flutter SDK 没有
这个值，一旦这份 Dart 代码进了所有平台都要编译的依赖树，`flutter analyze` /
`flutter build windows|android` 会直接编译失败。

`dart:io` 的 `Platform.operatingSystem` 在两个 SDK 上都有，鸿蒙上返回 `'ohos'`、
其它平台永远不会等于 `'ohos'`，所以同一份代码两边都能编译。仓库自己的
`lib/shared/utils/platform_helper.dart` 用的是同一条规则。

## 裁剪范围

保留了 `lib/`、`ohos/`、`android/`、`ios/`、`macos/`（pubspec 声明了这些平台，
原生目录缺失会让对应平台的构建失败）。裁掉了 `example/`（143 文件 / 12.25 MB，
含 LFS 大文件）、`test/`（依赖 mocktail）与仓库级杂项。

## 跟随上游

上游发新版时手工比对 `lib/` 的三个文件（`core.dart`、`audio_session.dart`、
新增的 `ohos.dart`）与 `ohos/` 目录即可。
