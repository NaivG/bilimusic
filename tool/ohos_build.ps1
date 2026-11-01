# OHOS 打包入口：固定使用 OpenHarmony Flutter SDK，并在构建期间锁住
# .dart_tool/package_config.json，防止 Flutter 分析服务用官方 SDK
# 覆盖。
#
# 用法：
#   .\tool\ohos_build.ps1                 # 模拟器 x64 debug
#   .\tool\ohos_build.ps1 -TargetPlatform ohos-arm64
#   .\tool\ohos_build.ps1 -Release
param(
  [ValidateSet('ohos-arm64', 'ohos-arm', 'ohos-x64')]
  [string]$TargetPlatform = 'ohos-x64',
  [switch]$Release
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutterSdk = if ($env:FLUTTER_SDK) { $env:FLUTTER_SDK } else { 'D:\flutter_flutter' }
$toolHome = if ($env:TOOL_HOME) { $env:TOOL_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }

if (-not (Test-Path "$flutterSdk\bin\flutter.bat")) {
  throw "找不到 OHOS Flutter SDK：$flutterSdk（设置 FLUTTER_SDK 或改脚本默认值）"
}
if (-not (Test-Path "$toolHome\sdk")) {
  throw "找不到 DevEco Studio：$toolHome（设置 TOOL_HOME 或改脚本默认值）"
}

$env:TOOL_HOME = $toolHome
$env:DEVECO_SDK_HOME = "$toolHome\sdk"
$env:HOS_SDK_HOME = "$toolHome\sdk"
$env:HDC_HOME = "$toolHome\sdk\default\openharmony\toolchains"
$env:PATH = "$toolHome\tools\node\bin;$toolHome\tools\hvigor\bin;$toolHome\tools\ohpm\bin;$flutterSdk\bin;$env:PATH"

# pub 缓存必须和工程在同一个盘符：flutter_tools 给 hvigor 写 build-profile.json5
# 的 modules[].srcPath 时用 path.relative()，跨盘只会退回绝对路径，hvigor 直接报
# "The srcPath is not a relative path"。
$env:PUB_CACHE = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { "$flutterSdk\cache\Pub\Cache" }

# git 依赖里若带 Git LFS 大文件，gitcode 的 LFS 端点不给匿名下载（batch 鉴权
# 失败会让 pub get 整个失败）。pub 只要源码树，跳过 smudge 即可 —— 拿到的
# LFS 文件是指针文本，只影响那个仓库的 example。
$env:GIT_LFS_SKIP_SMUDGE = '1'

# build-profile.json5 存的是本机签名材料（证书绝对路径 + 加密口令），不进仓库。
$buildProfile = Join-Path $root 'ohos\build-profile.json5'
if (-not (Test-Path $buildProfile)) {
  Copy-Item (Join-Path $root 'ohos\build-profile.json5.example') $buildProfile
  Write-Host '已从 build-profile.json5.example 生成 ohos/build-profile.json5，' -ForegroundColor Yellow
  Write-Host '签名请用 DevEco Studio 的 Project Structure > Signing Configs 自动签名。' -ForegroundColor Yellow
}

& "$flutterSdk\bin\flutter.bat" pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败" }

$configPath = Join-Path $root '.dart_tool\package_config.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$flutterPkg = $config.packages | Where-Object { $_.name -eq 'flutter' } | Select-Object -First 1
$expected = 'file:///' + (Resolve-Path "$flutterSdk\packages\flutter").Path.TrimStart('\').Replace('\', '/')
if ($flutterPkg.rootUri -ne $expected) {
  throw @"
package_config 指向了错误的 Flutter SDK：
  实际: $($flutterPkg.rootUri)
  期望: $expected
请关闭 DevEco Studio / 其它 IDE 的 Flutter 分析服务后重试；否则它会在构建中途把 package_config 改回官方 SDK，HAP 启动时报 "Unknown platform."。
"@
}

# ---- 原生库准备（libmpv 的运行时依赖）------------------------------------
# libmpv.so 的 DT_NEEDED 里有 libc++_shared.so：OHOS 系统的 libc++ 不在应用的
# linker namespace 里，直接 dlopen 会报 "needed by … 找不到"。从 DevEco SDK 的
# NDK 拷一份到 entry/libs/<abi>/，跟 libmpv.so 一起打包进 HAP。
$nativeAbi = @{
  'ohos-x64'   = @{ Dir = 'x86_64';      Triple = 'x86_64-linux-ohos' }
  'ohos-arm64' = @{ Dir = 'arm64-v8a';   Triple = 'aarch64-linux-ohos' }
  'ohos-arm'   = @{ Dir = 'armeabi-v7a'; Triple = 'arm-linux-ohos' }
}[$TargetPlatform]

$libsDir = Join-Path $root "ohos\entry\libs\$($nativeAbi.Dir)"
New-Item -ItemType Directory -Force -Path $libsDir | Out-Null

$stlSource = Join-Path $toolHome "sdk\default\openharmony\native\llvm\lib\$($nativeAbi.Triple)\libc++_shared.so"
$stlTarget = Join-Path $libsDir 'libc++_shared.so'
if (Test-Path $stlSource) {
  $stale = (-not (Test-Path $stlTarget)) -or ((Get-Item $stlTarget).Length -ne (Get-Item $stlSource).Length)
  if ($stale) {
    Copy-Item $stlSource $stlTarget -Force
    Write-Host "已从 NDK 补 libc++_shared.so -> ohos\entry\libs\$($nativeAbi.Dir)\" -ForegroundColor DarkGray
  }
} else {
  Write-Host "警告：找不到 $stlSource，libmpv 会因为缺 libc++_shared.so 加载失败" -ForegroundColor Yellow
}

if (-not (Test-Path (Join-Path $libsDir 'libmpv.so'))) {
  $libmpvHint = if ($TargetPlatform -eq 'ohos-x64') { '.\tool\build_libmpv_ohos.ps1' } else { '.\tool\build_libmpv_ohos.ps1 -Arch aarch64' }
  Write-Host "警告：ohos\entry\libs\$($nativeAbi.Dir)\libmpv.so 不存在，播放会退回占位模式。" -ForegroundColor Yellow
  Write-Host "      先跑 $libmpvHint 并把产物拷进该目录。" -ForegroundColor Yellow
}

# 构建期间禁止 IDE 改写；构建结束后恢复原状态。
$item = Get-Item $configPath
$wasReadOnly = $item.IsReadOnly
$item.IsReadOnly = $true
try {
  $buildArgs = @('build', 'hap', '--target-platform', $TargetPlatform, '--no-pub')
  if ($Release) {
    $buildArgs += '--release'
  } else {
    $buildArgs += '--debug'
  }
  & "$flutterSdk\bin\flutter.bat" @buildArgs
  if ($LASTEXITCODE -ne 0) { throw "flutter build hap 失败" }
} finally {
  (Get-Item $configPath).IsReadOnly = $wasReadOnly
}

Write-Host "HAP 输出：build\ohos\hap\entry-default-signed.hap"
