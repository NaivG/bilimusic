#!/usr/bin/env bash
# 校验产物：ELF 架构 / SONAME / 动态依赖 / 关键符号 / OHAudio 后端是否编进去
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

SO=$DEST/libmpv.so
READELF=$LLVM_BIN/llvm-readelf.exe
NM=$LLVM_BIN/llvm-nm.exe
STRINGS=$LLVM_BIN/llvm-strings.exe

if [ ! -f "$SO" ]; then
  echo "✗ 找不到产物：$SO" >&2
  exit 1
fi

case "$ARCH" in
  x86_64)  expect_machine="X86-64" ;;
  aarch64) expect_machine="AArch64" ;;
esac

fail=0
echo "产物：$SO（$(du -h "$SO" | cut -f1)）"
echo

echo "— ELF 头 —"
hdr=$("$READELF" -h "$SO")
echo "$hdr" | grep -E 'Class:|Machine:|Type:'
if echo "$hdr" | grep -q "$expect_machine"; then
  echo "  ✓ Machine = $expect_machine"
else
  echo "  ✗ Machine 不是 $expect_machine"; fail=1
fi
echo

echo "— 动态依赖 —"
dyn=$("$READELF" -d "$SO")
echo "$dyn" | grep -E 'SONAME|NEEDED' || true
# 允许的动态依赖 = 模拟器（x86_64 / OHOS 7.0.0，API 26）上确实可解析的库。
# 判据来自 `hdc shell test -e` 逐个探测（2026-11）：libohaudio/libGLESv2/libhilog_ndk
# 只在 /system/lib64/ndk；libnative_window/libnative_buffer/libace_napi 在 shell 的
# 命名空间里看不到，但 Flutter 引擎自己就带着这几个 NEEDED 且能跑，所以算可用。
allowed='^(libc\.so|libc\+\+_shared\.so|libc\+\+\.so|libunwind\.so|libclang_rt.*|libz\.so|libEGL\.so|libGLESv2\.so|libGLESv3\.so|libvulkan\.so|libohaudio\.so|libohaudiosuite\.so|libhilog\.so|libhilog_ndk\.z\.so|libhitrace_ndk\.z\.so|libhiappevent_ndk\.z\.so|libnative_buffer\.so|libnative_image\.so|libnative_window\.so|libnative_window_manager\.so|libnative_vsync\.so|libnative_drawing\.so|libnative_color_space_manager\.so|libnative_media_[a-z]+\.so|libace_[a-z_]+\.z\.so|libdeviceinfo_ndk\.z\.so|libffrt\.z\.so|libuv\.so|librawfile\.z\.so|libimage_ndk\.z\.so|libpixelmap[_a-z]*\.so|libimage_source\.so|libqos\.so|libboundscheck\.so)$'
bad=$(echo "$dyn" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | grep -Ev "$allowed" || true)
# 这几个在模拟器上真的不存在（musl 并进 libc / 镜像里没有），出现就是硬故障
risky='^(libm\.so|libdl\.so|libpthread\.so|liblzma\.so|libbz2\.so|libssl\.so.*|libcrypto\.so.*)$'
risky_hit=$(echo "$dyn" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | grep -E "$risky" || true)
if [ -n "$risky_hit" ]; then
  echo "  ✗ 依赖了模拟器上不存在的库："; echo "$risky_hit" | sed 's/^/    /'; fail=1
fi
if [ -n "$bad" ]; then
  echo "  ✗ 出现了非 OHOS 系统库依赖（装进 HAP 后会 dlopen 失败）："; echo "$bad" | sed 's/^/    /'; fail=1
else
  echo "  ✓ 动态依赖全部落在 OHOS 系统库范围内"
fi
echo

echo "— 关键符号 —"
# 先把导出符号落到临时文件：直接 `nm | grep -q` 会提前关管道，llvm-nm 会刷
# "LLVM ERROR: IO failure on output stream" 并返回非 0。
"$NM" -D --defined-only "$SO" > "$WORK_DIR/.nm-defined.txt" 2>/dev/null || true
"$NM" -D --undefined-only "$SO" > "$WORK_DIR/.nm-undefined.txt" 2>/dev/null || true
for sym in mpv_create mpv_initialize mpv_command mpv_set_property mpv_wait_event mpv_terminate_destroy; do
  if grep -qE " T ${sym}$" "$WORK_DIR/.nm-defined.txt"; then
    echo "  ✓ $sym"
  else
    echo "  ✗ 缺少导出符号 $sym"; fail=1
  fi
done
echo

echo "— 音频后端 —"
if "$STRINGS" "$SO" 2>/dev/null | grep -qx 'ohaudio'; then
  echo "  ✓ 编入了 OHOS OHAudio 输出（ao_ohaudio）"
else
  echo "  ? 没有在字符串里找到 'ohaudio'，用 --ao=help 在设备上确认"
fi
if "$STRINGS" "$SO" 2>/dev/null | grep -qx 'ao_null\|null'; then
  echo "  ✓ 有 null 音频输出（可用作兜底）"
fi
echo

echo "— 未解析符号数 —"
undef=$("$NM" -D --undefined-only "$SO" | wc -l)
echo "  $undef 个（全部应可由上面列出的系统库提供）"

echo
if [ "$fail" -ne 0 ]; then
  echo "✗ 校验未通过" >&2
  exit 1
fi
echo "✓ 校验通过：$SO"
