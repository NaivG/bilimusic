# libmpv for OpenHarmony（`tool/ohos_libmpv`）

给 Flutter 端 `mpv_audio_kit` 用的 **OpenHarmony libmpv 交叉编译脚本**。

## 目录结构

```
tool/ohos_libmpv/
├── build.sh               # 入口：fetch → patch → deps → verify
├── env.sh                 # ARCH / SDK / 交叉工具链 / meson cross-file 生成
├── versions.sh            # 上游依赖版本（与 deps-version.sh 对齐）
├── fetch.sh               # 拉源码（浅克隆 / 源码包）
├── patch.sh               # 打 libplacebo 补丁
├── deps.sh                # 逐组件编译，成功打戳可续跑
├── verify.sh              # ELF / 依赖 / 符号 校验
├── check_symbols.sh       # 未解析符号 vs 系统库导出的覆盖检查
├── smoke_test.c/.sh       # 设备端冒烟（见上方「现状」里的限制说明）
├── crossfiles/            # meson 交叉文件模板
└── patches/libplacebo/    # 上游那两个补丁
```

## 前置

1. **MSYS2**（便携版即可，不需要装 mingw 工具链）：

   ```powershell
   # 解压 msys2-base-x86_64-*.tar.xz 到 D:\msys64，然后：
   D:\msys64\usr\bin\bash.exe -lc "pacman -Syu --noconfirm"
   D:\msys64\usr\bin\bash.exe -lc "pacman -S --needed --noconfirm make python python-pip meson ninja pkgconf gperf wget unzip zip nasm git diffutils patch gcc"
   ```

   - `gcc` 是给 ffmpeg 的 **host 工具**用的（configure 要跑 host 编译器探测，缺了会报
     `Host compiler lacks C11 support`）。
   - meson 必须是 **原生 Windows 版**（`pip install meson` 到 Windows 的 Python）；
     MSYS2 的 `pacman` 版 meson 跑在 MSYS Python 上，会把 `D:/...` 当相对路径。
     `env.sh` 会自动去 `%LOCALAPPDATA%\Programs\Python\Python3*\Scripts\meson.exe` 找，
     也可以用 `MESON=...` 指定。
   - mbedtls 的 PSA 代码生成脚本需要 `jsonschema`，MSYS2 的 Python 装不上
     （依赖的 `rpds-py` 要 Rust 编译）。`deps.sh` 的做法是 `touch` 发布包里自带的
     生成产物，让它不触发代码生成；因此 mbedtls 只编 `lib` 并手工安装。

2. **DevEco Studio 的 OHOS SDK**（API 26）。SDK 默认装在
   `C:\Program Files\...`，路径带空格会让 meson/cmake 的交叉文件拆词，
   `tool/build_libmpv_ohos.ps1` 会自动在工作目录建 junction 映射成无空格路径。

## 用法

```powershell
.\tool\build_libmpv_ohos.ps1                     # x86_64（模拟器，默认）
.\tool\build_libmpv_ohos.ps1 -Arch aarch64       # 真机
.\tool\build_libmpv_ohos.ps1 -Step verify        # 只校验产物
```

纯 bash 也行（`ARCH` / `OHOS_NDK_HOME` / `WORK_DIR` 可用环境变量覆盖）：

```bash
D:/msys64/usr/bin/bash.exe -l tool/ohos_libmpv/build.sh
```

产物与中间文件都不进仓库，默认落在 `D:\ohos-libmpv`：

```
D:\ohos-libmpv\
├── src\                  # 各依赖源码（两个架构共用）
│   └── .build-arch       # 源码树上一次用于哪个架构；换架构时 deps.sh 依它清 in-tree 目标文件
├── x86_64-build\         # 安装前缀（libmpv.so 在根上）
│   ├── libmpv.so         ← 产物
│   ├── lib\*.a           # 静态依赖（全部静态链接进 libmpv.so）
│   └── .stamps\          # 已完成的组件（删掉即可重编该组件）
└── logs\                 # 每个组件的构建日志
```

`src\` 由两个架构共用，而 mbedtls / ffmpeg / lua 是 in-tree 构建（目标文件直接落在源码
目录里）。换架构时 `deps.sh` 会先清掉别的架构的目标文件并让 mbedtls 重装一遍，所以
**同一份 `WORK_DIR` 可以交替构建，但不要同时跑两个架构**（会互相清对方的目标文件）。

## 校验

`verify.sh`（`-Step verify`）检查：

- ELF `Machine` 与目标架构一致；
- `SONAME` 与全部 `DT_NEEDED` —— 只允许 OHOS 系统库，出现别的名字说明有依赖没静态链进去，
  装到 HAP 里会 `dlopen` 失败；
- `mpv_create` / `mpv_command` / `mpv_wait_event` 等 libmpv 导出符号存在；
- 二进制里能找到 `ohaudio`（OHOS 音频输出驱动 `audio/out/ao_ohaudio.c`）。

`smoke_test.sh`（`-Step smoke`）是真机验证：把 `libmpv.so`、冒烟程序和一个 3 秒正弦
wav 推到 `/data/local/tmp`，`mpv_create → ao=ohaudio → loadfile` 跑一遍，打印
`current-ao` / `time-pos` / 事件流，全过打印 `SMOKE PASS`。**注意**：`hdc shell` 是
shell 域，拉起 `libnative_media_*` 时会连带加载 ArkTS 运行时并报一堆
`symbol not found`（`libark_jsruntime.so` 在 shell 域不可用），这是环境限制；真正跑通要
在 HAP 应用进程里验。

`check_symbols.sh` 是交叉验证：把 `libmpv.so` 的全部未解析符号，跟 `DT_NEEDED` 里每个
系统库的导出符号对账。当前结果：**400 个未解析符号，4527 个系统导出能覆盖，只差一个
weak 的 `__at_fini`**（weak 找不到就当 0，不影响加载）。

## 排错

| 现象 | 处理 |
| --- | --- |
| `找不到 MSYS2` | 用 `-Msys D:\msys64` 指定解压位置 |
| `OpenHarmony SDK 不完整` | `OHOS_NDK_HOME` 要指到平台根目录（其下有 `native/`），不是 `sdk/` |
| meson 报找不到 `vulkan`/`zlib` | 先跑 `deps.sh syspc`（`build.sh` 的 all 已包含） |
| `libplacebo compiled without vulkan support!` | 用 `WITH_VIDEO=0` 重编 libplacebo 与 mpv，或先编 shaderc 再开视频 |
| ffmpeg configure 报 `nasm/yasm not found` | MSYS2 里 `pacman -S nasm` |
| ffmpeg configure 报 `ERROR: mbedTLS not found` | 真因看 `src\ffmpeg\ffbuild\config.log`。若出现 `libmbedtls.a(...) is incompatible with aarch64linux`，说明 `src` 里混了别的架构的目标文件：删掉 `src\.build-arch` 后重跑（`deps.sh` 会重新清理并让 mbedtls 重装），或手工 `rm -f $DEST/.stamps/mbedtls.done` |
| 想重编某个组件 | 删 `$DEST/.stamps/<组件>.done` 后重跑 |