# `file_picker`（vendored）

这是 [file_picker](https://pub.dev/packages/file_picker) **10.3.10** 的整包副本，
只为补一份 OpenHarmony 平台实现。上游发布在 pub.dev，这里不从上游仓库直接引用。

## 为什么不能做成「独立平台实现包」

`file_picker` 10.x **不是联邦化插件**：没有 platform interface，Android / iOS /
macOS 的方法通道与平台选择全部内联在 front-end 的 Dart 代码里，因此没法像
`share_plus_ohos` / `audio_service_ohos` 那样只补一个 `platforms.ohos` 的实现包。

## 为什么不用社区的 `file_picker_ohos` 仓库

CPF-Flutter 的适配仓库（`fluttertpc_file_picker`）基于 10.3.8，把 Dart 包名改成了
`file_picker_ohos`，但 `ios/file_picker.podspec` 里的 `s.name` 仍然是 `file_picker`。
CocoaPods 会按插件包名去找 `file_picker_ohos.podspec`，于是直接爆炸。

## 相对上游 10.3.10 的改动

1. `pubspec.yaml` 增加 `flutter.plugin.platforms.ohos`，并声明
   `dartPluginClass: FilePickerIO`（鸿蒙 SDK 会生成 Dart 注册项；官方 SDK 会忽略
   这个平台键）。
2. 新增 `ohos/`（来自 `fluttertpc_file_picker` 的 10.3.8 适配），只把
   `oh-package.json5` 与 `src/main/module.json5` 的包名改成 `file_picker`，与 Dart
   包名、生成的 `GeneratedPluginRegistrant.ets` 对齐。
3. `lib/src/file_picker_io.dart` 的 `saveFile()` 增加
   `Platform.operatingSystem == 'ohos'` 分支，让鸿蒙和 Android / iOS 一样走
   `save` 通道（必须带 `bytes`）。
4. 修复 `ohos/` 的 `save` 通道：Dart 传进来的 `bytes` 之前被读出来却没用，
   `FilePickerDelegate.saveFile()` 检查的 `bytesList` 是空的。现在先调用
   `setPendingBytes()`，保存时才能拿到真实内容。

**平台判定一律用 `Platform.operatingSystem == 'ohos'`**，不要用只有鸿蒙 SDK 才有
的 `Platform.isOhos` / `TargetPlatform.ohos`，否则官方 Flutter SDK 下编译失败。

## 裁剪范围

保留 `lib/`、`android/`、`ios/`、`macos/`、`ohos/`。裁掉 `example/`、`test/` 与
仓库级杂项（与 `packages/audio_session` 的处理一致）。

## 跟随上游

上游发新版时，手工把新版本的 `lib/`、`android/`、`ios/`、`macos/` 替换进来，然后
重做上面 3 条改动即可。`ohos/` 目录目前没有上游持续维护，改动前先在鸿蒙真机/模拟器
上回归选择文件、选择目录、保存文件三条路径。
