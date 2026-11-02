/// audio_service 的 OpenHarmony / HarmonyOS 平台实现。
///
/// 本包没有 Dart 侧胶水，也不需要 `dartPluginClass`：
/// `audio_service_platform_interface` 的默认实例本来就是
/// `MethodChannelAudioService`，而 `audio_service` 的 front-end 代码在
/// Windows / Linux 之外一律使用该默认实例。OHOS 侧只负责在 ArkTS 里实现
/// 这两个方法通道（见 `ohos/src/main/ets/AudioServicePlugin.ets`）：
///
/// - [clientChannel]：Dart → 平台，`configure` / `setState` / `setQueue` /
///   `setMediaItem` / `stopService` 等；
/// - [handlerChannel]：平台 → Dart，播放控制按键回调到 `AudioHandler`。
///
/// 通道名必须与 ArkTS 侧的字面量保持一致。
library;

/// Dart 侧调用平台实现所用的方法通道名。
const String clientChannel = 'com.ryanheise.audio_service.client.methods';

/// 平台把媒体控制事件回传给 Dart 所用的方法通道名。
const String handlerChannel = 'com.ryanheise.audio_service.handler.methods';
