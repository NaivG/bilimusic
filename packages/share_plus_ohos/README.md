# `share_plus_ohos`

`share_plus` 的 OpenHarmony / HarmonyOS 平台实现。**联邦化实现包**：front-end 仍是
pub.dev 上的 `share_plus`，本包只补 `ohos` 一个平台。

## 已知行为

`share()` 不带 `WithResult` 时，ArkTS 侧按 share_plus 的约定回
`dev.fluttercommunity.plus/share/unavailable`，即「分享面板已打开，但拿不到用户
选择结果」。这是该平台的能力边界，不是本包的缺陷。

## 验证

```powershell
.\tool\ohos_build.ps1
# GeneratedPluginRegistrant.ets 应出现：
#   import SharePlusOhosPlugin from 'share_plus_ohos';
```

真机上在歌曲详情页点一次分享，确认系统分享面板能拉起。
