#!/usr/bin/env bash
# libmpv for OpenHarmony：公共环境（路径 / 交叉工具链 / 目标架构）
#
# 本文件由 build.sh source，也可以单独 source 后手工跑某一步：
#   ARCH=x86_64 OHOS_NDK_HOME=D:/ohos-sdk source tool/ohos_libmpv/env.sh
#
# 可覆盖的变量：
#   ARCH           x86_64（默认，模拟器）| aarch64（真机）
#   OHOS_NDK_HOME  OpenHarmony SDK 平台根目录，其下必须有 native/（默认 D:/ohos-sdk）
#   WORK_DIR       源码与产物的落点（默认 D:/ohos-libmpv，不放进仓库）
set -eu

# 仓库内本目录（Windows 形式的绝对路径，meson / cmake 只认这种形式）
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W 2>/dev/null || pwd)

# Windows 路径转 MSYS 形式（`D:/foo` -> `/d/foo`）。PATH / PKG_CONFIG_PATH 这类
# 带冒号分隔的变量只能用这种形式：MSYS 按冒号切分，`D:` 会被切成两段。
win2msys() {
  case "$1" in
    [A-Za-z]:/*)
      local drive
      drive=$(printf '%s' "$1" | cut -c1 | tr 'A-Z' 'a-z')
      printf '/%s/%s' "$drive" "$(printf '%s' "$1" | cut -c4-)"
      ;;
    *) printf '%s' "$1" ;;
  esac
}

# ---------------- 目标架构 ----------------
ARCH=${ARCH:-x86_64}
case "$ARCH" in
  x86_64|amd64)
    ARCH=x86_64
    TRIPLE=x86_64-linux-ohos
    ABI=x86_64
    CPU_FAMILY=x86_64
    CPU=x86_64
    FF_ARCH=x86_64
    FF_CPU=x86-64
    ;;
  aarch64|arm64)
    ARCH=aarch64
    TRIPLE=aarch64-linux-ohos
    ABI=arm64-v8a
    CPU_FAMILY=aarch64
    CPU=aarch64
    FF_ARCH=aarch64
    FF_CPU=armv8-a
    ;;
  *)
    echo "不支持的 ARCH: $ARCH（可选 x86_64 / aarch64）" >&2
    exit 2
    ;;
esac
export ARCH TRIPLE ABI CPU_FAMILY CPU FF_ARCH FF_CPU

# ---------------- SDK 与工具链 ----------------
OHOS_NDK_HOME=${OHOS_NDK_HOME:-D:/ohos-sdk}
OHOS_NDK_HOME=${OHOS_NDK_HOME%/}
SYSROOT=$OHOS_NDK_HOME/native/sysroot
LLVM_BIN=$OHOS_NDK_HOME/native/llvm/bin
CMAKE_BIN=$OHOS_NDK_HOME/native/build-tools/cmake/bin

for f in "$LLVM_BIN/clang.exe" "$SYSROOT/usr/lib/$TRIPLE/libc.so"; do
  if [ ! -e "$f" ]; then
    echo "OpenHarmony SDK 不完整，缺少：$f" >&2
    echo "请设置 OHOS_NDK_HOME 指向 SDK 平台根目录（其下有 native/）" >&2
    exit 2
  fi
done

# ---------------- 目录 ----------------
WORK_DIR=${WORK_DIR:-D:/ohos-libmpv}
WORK_DIR=${WORK_DIR%/}
SRC_DIR=$WORK_DIR/src
DEST=$WORK_DIR/$ARCH-build
TOOLCHAIN_DIR=$WORK_DIR/toolchain/$ARCH
LOG_DIR=$WORK_DIR/logs
mkdir -p "$SRC_DIR" "$DEST" "$TOOLCHAIN_DIR" "$LOG_DIR"

# ---------------- 交叉编译变量 ----------------
# make 系（mbedtls / lua）用包装脚本，避免空格拆词；meson 系用 cross-file 里的显式参数
write_wrapper() {
  local name=$1 target=$2
  printf '#!/usr/bin/env bash\nexec "%s/%s" --target=%s --sysroot=%s "$@"\n' \
    "$LLVM_BIN" "$target" "$TRIPLE" "$SYSROOT" > "$TOOLCHAIN_DIR/$name"
  chmod +x "$TOOLCHAIN_DIR/$name"
}
write_wrapper cc clang.exe
write_wrapper cxx clang++.exe

export CC="$TOOLCHAIN_DIR/cc"
export CXX="$TOOLCHAIN_DIR/cxx"
export AR="$LLVM_BIN/llvm-ar.exe"
export RANLIB="$LLVM_BIN/llvm-ranlib.exe"
export STRIP="$LLVM_BIN/llvm-strip.exe"
export NM="$LLVM_BIN/llvm-nm.exe"
export OBJCOPY="$LLVM_BIN/llvm-objcopy.exe"
export OBJDUMP="$LLVM_BIN/llvm-objdump.exe"
export AS="$LLVM_BIN/llvm-as.exe"
export LD="$LLVM_BIN/ld.lld.exe"
export CFLAGS='-fPIC -D__MUSL__=1'
export CXXFLAGS='-fPIC -D__MUSL__=1'

# 依赖装进 $DEST，宿主 pkg-config 只认它 + SDK sysroot，绝不回落到宿主库。
# 路径必须是 MSYS 形式（`/d/...`）：MSYS 的 pkg-config 按冒号切变量，写成 `D:/...`
# 会被切成 `D` + `/ohos-...`（和 PATH 同一个坑）。
export PKG_CONFIG_PATH="$(win2msys "$DEST")/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$(win2msys "$SYSROOT")/usr/lib"
unset PKG_CONFIG_SYSROOT_DIR || true

# meson 要的是「原生 Windows」pkg-config：它在原生进程里被调起时，MSYS 会把
# PKG_CONFIG_PATH 转成 Windows 形式（`D:/...`），MSYS 版 pkg-config 再按冒号切就废了。
# MSYS2 仓库里的 mingw-w64-x86_64-pkgconf 是原生构建，能正确处理这种路径。
MSYS_ROOT=$(cd /usr/.. && pwd -W 2>/dev/null || printf 'C:/msys64')
PKG_CONFIG_NATIVE=$MSYS_ROOT/mingw64/bin/pkgconf.exe
if [ ! -e "$PKG_CONFIG_NATIVE" ]; then
  echo "警告：找不到原生 pkg-config（$PKG_CONFIG_NATIVE）。" >&2
  echo "      meson 系依赖会解析不到彼此的 .pc；执行 pacman -S mingw-w64-x86_64-pkgconf" >&2
  PKG_CONFIG_NATIVE=pkg-config
fi

# ---------------- meson / ninja ----------------
# 必须用「原生 Windows」版 meson：MSYS2 自带的 meson 跑在 MSYS Python 上，会把
# `D:/...` 当成非绝对路径（setup 直接报 "prefix must be an absolute path"）。
# ninja 用 SDK 自带的那份（native/build-tools/cmake/bin/ninja.exe），与 cmake 同源。
localapp=$(printf '%s' "${LOCALAPPDATA:-}" | tr '\\' '/')
find_meson() {
  if [ -n "${MESON:-}" ] && [ -e "${MESON}" ]; then echo "$MESON"; return 0; fi
  local cand
  for cand in "$localapp"/Programs/Python/Python3*/Scripts/meson.exe \
              "$localapp"/Programs/Python/Python3*/bin/meson.exe \
              "$USERPROFILE"/AppData/Local/Programs/Python/Python3*/Scripts/meson.exe; do
    [ -e "$cand" ] && { echo "$cand"; return 0; }
  done
  command -v meson 2>/dev/null || true
}
MESON=$(find_meson)
if [ -z "${MESON:-}" ]; then
  echo "找不到原生 Windows 版 meson（pip install meson 到 Windows Python）" >&2
  echo "MSYS2 里 pacman 装的那个不能用：它把 D:/ 当相对路径。" >&2
  exit 2
fi
if [ -e "$CMAKE_BIN/ninja.exe" ]; then
  NINJA=$CMAKE_BIN/ninja.exe
else
  NINJA=$(command -v ninja)
fi

# meson 是原生 Windows 程序，会把 Windows 路径（反斜杠）直接传给依赖里的
# `find_program('python3')`；MSYS2 的 /usr/bin/python3 打不开 `D:\...` 这种路径
# （freetype 的 extract_libtool_version.py 就是这么挂的）。因此把 Windows Python
# 目录排在 PATH 最前，让 meson 解析到原生 python3.exe。
PY_DIR=$(dirname "$(dirname "$MESON")")
# Windows 版 CPython 不装 python3.exe；meson 的 find_program('python3') 找不到它时会
# 退回 MSYS 的 python3，而那个打不开 `D:\...` 形式的路径（freetype 的
# extract_libtool_version.py 就是这么挂的）。补一个同名拷贝即可（python.exe 按自身
# 目录找 python3xx.dll，同目录复制不会坏）。
if [ ! -e "$PY_DIR/python3.exe" ] && [ -e "$PY_DIR/python.exe" ]; then
  cp -f "$PY_DIR/python.exe" "$PY_DIR/python3.exe" 2>/dev/null || true
fi
export PATH="$(win2msys "$PY_DIR"):$(win2msys "$CMAKE_BIN"):$(win2msys "$LLVM_BIN"):$PATH"
export MESON NINJA

export CORES=$(nproc 2>/dev/null || echo 4)
if [ "$CORES" -gt 8 ]; then CORES=8; fi
export CORES

# ---------------- meson cross-file ----------------
# 由模板生成：把 SDK 路径 / triple / cpu 填进去（模板里的 @占位符@）
CROSS_FILE=$WORK_DIR/$ARCH-crossfile.ini
generate_cross_file() {
  sed -e "s|@SDK@|$OHOS_NDK_HOME|g" \
      -e "s|@TRIPLE@|$TRIPLE|g" \
      -e "s|@CPU_FAMILY@|$CPU_FAMILY|g" \
      -e "s|@CPU@|$CPU|g" \
      -e "s|@PKG_CONFIG@|$PKG_CONFIG_NATIVE|g" \
      "$ROOT_DIR/crossfiles/crossfile-linux.ini.in" > "$CROSS_FILE"
}
generate_cross_file

export ROOT_DIR OHOS_NDK_HOME SYSROOT LLVM_BIN WORK_DIR SRC_DIR DEST TOOLCHAIN_DIR LOG_DIR CROSS_FILE
