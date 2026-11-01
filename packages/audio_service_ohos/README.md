# `audio_service_ohos`

`audio_service` 的 OpenHarmony / HarmonyOS 平台实现。**联邦化实现包**：front-end 仍是
pub.dev 上的 `audio_service`，本包只补 `ohos` 一个平台。

## 验证

```powershell
.\tool\ohos_build.ps1
# 生成物里应能看到：
#   ohos/entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets
#     import AudioServicePlugin from 'audio_service_ohos';
#   .flutter-plugins-dependencies 的 plugins.ohos 里出现 audio_service_ohos
```
