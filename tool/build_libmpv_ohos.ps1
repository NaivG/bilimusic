<#
.SYNOPSIS
  为 OpenHarmony 交叉编译 libmpv（默认 x86_64，模拟器调试用）。

.DESCRIPTION
  本脚本只负责：找 MSYS2、把 OHOS SDK 挂到一个没有空格的路径、
  导出 ARCH / WORK_DIR，然后调 build.sh。

  前置：
    - MSYS2（便携解压即用，装到 D:\msys64 即可），并已安装 make/python/meson/ninja/
      pkgconf/gperf/wget/unzip/zip/nasm/git（见 tool/ohos_libmpv/README.md）
    - DevEco Studio 的 OpenHarmony SDK（含 native/）

.EXAMPLE
  .\tool\build_libmpv_ohos.ps1                     # x86_64
  .\tool\build_libmpv_ohos.ps1 -Arch aarch64       # 真机 arm64
  .\tool\build_libmpv_ohos.ps1 -Step verify        # 只校验已有产物
#>
param(
  [ValidateSet('x86_64', 'aarch64')]
  [string]$Arch = 'x86_64',
  [ValidateSet('all', 'fetch', 'patch', 'deps', 'verify')]
  [string]$Step = 'all',
  [string]$Msys = 'D:\msys64',
  [string]$WorkDir = 'D:\ohos-libmpv'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'tool\ohos_libmpv\build.sh'

$bash = Join-Path $Msys 'usr\bin\bash.exe'
if (-not (Test-Path $bash)) {
  throw "找不到 MSYS2：$bash（用 -Msys 指定解压位置，见 tool/ohos_libmpv/README.md）"
}

# OHOS SDK：优先 env，其次 DevEco Studio 默认安装位置
$sdk = $env:OHOS_NDK_HOME
if (-not $sdk) {
  $toolHome = if ($env:TOOL_HOME) { $env:TOOL_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }
  $sdk = Join-Path $toolHome 'sdk\default\openharmony'
}
if (-not (Test-Path (Join-Path $sdk 'native\llvm\bin\clang.exe'))) {
  throw "找不到 OpenHarmony SDK 的 native 工具链：$sdk（设置 OHOS_NDK_HOME）"
}

# SDK 的默认安装路径带空格（Program Files），meson / cmake 的交叉文件里路径带空格
# 会被拆词。工作目录建一个 junction，把它映射成无空格路径。
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$sdkLink = Join-Path $WorkDir 'sdk'
if (-not (Test-Path $sdkLink)) {
  cmd /c mklink /J "$sdkLink" "$sdk" | Out-Null
}
$sdkWin = (Resolve-Path $sdkLink).Path.Replace('\', '/')
$workWin = (Resolve-Path $WorkDir).Path.Replace('\', '/')

$env:OHOS_NDK_HOME = $sdkWin
$env:WORK_DIR = $workWin
$env:ARCH = $Arch

Write-Host "SDK      : $sdk  ->  $sdkWin"
Write-Host "工作目录 : $workWin"
Write-Host "架构     : $Arch"
Write-Host "步骤     : $Step"
Write-Host ''

& $bash -l $script $Step
if ($LASTEXITCODE -ne 0) {
  throw "libmpv 构建失败（LOG 在 $workWin\logs）"
}

Write-Host ''
Write-Host "产物：$workWin\$Arch-build\libmpv.so"
