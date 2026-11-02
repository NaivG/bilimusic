#!/usr/bin/env bash
# libmpv for OpenHarmony：逐个编译依赖并安装到 $DEST
#
# 设计：每个组件成功后在 $DEST/.stamps 打戳，失败即停并打印该组件日志尾部。
# 可单独执行：  ./deps.sh mpv      # 只跑 mpv 这一步（前置步骤仍需已有戳）
#
# 可用开关：
#   WITH_VIDEO=0  只出头音频库：不建 shaderc，libplacebo 不开 vulkan/opengl（默认，见下方说明）
#   WITH_LUA=0    编译 Lua（默认关：mpv_audio_kit 不用 mpv 脚本）
#   WITH_DAV1D=0  编译 dav1d（AV1 解码，纯视频用途）
#   WITH_DOVI=0   libplacebo 的 Dolby Vision 支持（需要 Rust 的 OHOS target，x64 上没有预编译 std）
#
# 默认 WITH_VIDEO=0：mpv_audio_kit 只用 libmpv 的音频能力，视频链路会在 DT_NEEDED 里
# 带上一串 GPU/hwdec 库（EGL/GLESv2/vulkan/…），模拟器上徒增加载失败面，且 shaderc 是
# 整个依赖链里最重的一环。要出「和上游 arm64 完全同构」的库时再 WITH_VIDEO=1。
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. "$ROOT_DIR/versions.sh"

WITH_VIDEO=${WITH_VIDEO:-0}
WITH_LUA=${WITH_LUA:-0}
WITH_DAV1D=${WITH_DAV1D:-0}
WITH_DOVI=${WITH_DOVI:-0}

stamps=$DEST/.stamps
mkdir -p "$stamps" "$DEST/lib/pkgconfig"
done_ok() { [ -f "$stamps/$1.done" ]; }

step() { # $1=名字 $2=函数名（剩余参数透传给函数）
  local name=$1 fn=$2
  shift 2
  if done_ok "$name"; then
    echo "── 跳过 $name（已构建）"
    return 0
  fi
  local log=$LOG_DIR/$name.log
  : > "$log"
  echo "── 构建 $name"
  if ( cd "$SRC_DIR" && "$fn" "$@" ) >>"$log" 2>&1; then
    date '+%F %T' > "$stamps/$name.done"
    echo "   ✅ $name"
  else
    echo "   ❌ $name 失败，日志尾部（$log）：" >&2
    tail -n 60 "$log" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- 源码树架构隔离
# mbedtls / ffmpeg / lua 是 in-tree 构建：目标文件直接落在 $SRC_DIR 里，而这个目录由
# 两个架构共用。换架构时不清掉上一个架构的 .o，make 只按时间戳判断新鲜度，会把它们
# 原样打进新架构的 .a —— ffmpeg configure 的探测于是报
#   ld.lld: error: .../libmbedtls.a(debug.o) is incompatible with aarch64linux
# 表面现象却是 "ERROR: mbedTLS not found"（真因只在 ffbuild/config.log 里）。
clean_in_tree() {
  local ms=$SRC_DIR/mbedtls ff=$SRC_DIR/ffmpeg lua=$SRC_DIR/lua
  # 只删目标文件与归档：mbedtls 的 `make clean` 会连发行包里预生成的 PSA 包装一起删掉，
  # 删了就得用装不上的 jsonschema 重新生成
  if [ -d "$ms" ]; then
    find "$ms" \( -name '*.o' -o -name '*.a' \) -exec rm -f {} +
  fi
  if [ -d "$ff" ]; then
    # distclean 按 config.mak 里启用的库逐目录删 *.o/*.d/*.a，与架构无关
    if [ -f "$ff/ffbuild/config.mak" ]; then
      ( cd "$ff" && make distclean ) > "$LOG_DIR/clean-ffmpeg.log" 2>&1 || true
    fi
    # config.mak 坏掉时 distclean 跑不动，按后缀兜底
    find "$ff" -path "$ff/.git" -prune -o \
      \( -name '*.o' -o -name '*.d' -o -name '*.ho' -o -name '*.a' \) -exec rm -f {} +
    rm -f "$ff/config.h" "$ff/config.asm" "$ff/config_components.h" \
      "$ff/ffbuild/.config" "$ff"/ffbuild/config.*
  fi
  if [ -d "$lua" ]; then
    ( cd "$lua" && make clean ) > /dev/null 2>&1 || true
  fi
}

arch_file=$SRC_DIR/.build-arch
prev_arch=$(cat "$arch_file" 2>/dev/null || true)
if [ "$prev_arch" != "$ARCH" ]; then
  if [ -n "$prev_arch" ]; then
    echo "── 源码树上一个架构是 $prev_arch，先清掉它的 in-tree 目标文件（本次 $ARCH）"
  else
    echo "── 源码树没有架构标记，按干净树处理（清掉可能残留的 in-tree 目标文件）"
  fi
  clean_in_tree
  # src 已清空：这个架构以往装好的归档不再作数，让 mbedtls / lua 重新装一遍
  rm -f "$stamps/mbedtls.done" "$stamps/lua.done"
  printf '%s\n' "$ARCH" > "$arch_file"
fi

# ---------------------------------------------------------------- 系统库 .pc
# OHOS SDK 的 sysroot 不带 pkg-config 文件，而 meson 系依赖（libplacebo/mpv）用
# dependency('vulkan') 之类的探测。这里按 sysroot 实际情况补最小 .pc。
sys_pc() {
  local inc=$SYSROOT/usr/include
  local lib=$SYSROOT/usr/lib/$TRIPLE
  write_pc() { # $1=名字 $2=版本 $3=Libs
    cat > "$DEST/lib/pkgconfig/$1.pc" <<EOF
prefix=$SYSROOT/usr
includedir=$inc
libdir=$lib
Name: $1
Description: OpenHarmony SDK sysroot $1
Version: $2
Libs: -L\${libdir} $3
Cflags: -I\${includedir}
EOF
  }
  write_pc vulkan 1.3.309 -lvulkan
  write_pc egl 1.5 -lEGL
  write_pc glesv2 3.2 -lGLESv2
}

# ---------------------------------------------------------------- mbedtls
b_mbedtls() {
  cd mbedtls
  # 发布包里已经带了 PSA 生成产物（psa_crypto_driver_wrappers.*）；把它们的 mtime
  # 推到脚本之后，make 就不会去跑 generate_*.py —— 那个脚本要 jsonschema，而 MSYS2
  # 的 Python 装不上（rpds-py 需要 Rust 编译）。
  touch library/psa_crypto_driver_wrappers.h \
        library/psa_crypto_driver_wrappers_no_static.h \
        library/psa_crypto_driver_wrappers_no_static.c
  make -j"$CORES" lib CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS -O2" || return 1
  # 手工安装：make install 会顺带编 programs/tests（还要另一套 Python 生成）
  mkdir -p "$DEST/lib" "$DEST/include"
  cp -f library/libmbedcrypto.a library/libmbedx509.a library/libmbedtls.a "$DEST/lib/" || return 1
  cp -r include/mbedtls include/psa "$DEST/include/" || return 1
}

# ---------------------------------------------------------------- ffmpeg
b_ffmpeg() {
  cd ffmpeg
  local extra_pc=""
  if [ "$WITH_DAV1D" = "1" ]; then extra_pc="$extra_pc --enable-libdav1d"; fi
  # shellcheck disable=SC2086
  ./configure \
    --prefix="$DEST" \
    --arch="$FF_ARCH" --cpu="$FF_CPU" \
    --target-os=linux \
    --enable-static --disable-shared --enable-version3 --enable-pic \
    --disable-doc --disable-programs \
    --enable-cross-compile \
    --cc="$CC" \
    --extra-cflags="-I$DEST/include -fPIC -D__MUSL__=1" \
    --extra-ldflags="-L$DEST/lib" \
    --enable-mbedtls \
    --disable-vulkan --disable-zlib \
    --disable-devices --disable-avdevice --disable-muxers --disable-encoders \
    --enable-encoder=png,mjpeg \
    --enable-ohcodec \
    $extra_pc || return 1
  make -j"$CORES" || return 1
  make install || return 1
}

# 依赖前缀：预算成 "$DEST" 会踩 meson 的「prefix 必须是目标机绝对路径」校验——
# 交叉编译时 host_machine.system=linux，meson 用 PurePosixPath 判绝对性，`D:/…` 不算。
# 所以统一用 POSIX 的 `/` 作 prefix，靠 DESTDIR 把文件落到 $DEST，装完再把
# pkg-config 里的 `prefix=/` 改回 Windows 绝对路径（后面的依赖靠它找到头文件/库）。
pc_fixup() {
  local pc
  for pc in "$DEST"/lib/pkgconfig/*.pc "$DEST"/share/pkgconfig/*.pc; do
    [ -f "$pc" ] || continue
    sed -i "s|^prefix=/\$|prefix=$DEST|" "$pc"
  done
}

# ---------------------------------------------------------------- 纯 meson 依赖
meson_setup() { # $1=构建目录，其余是 meson setup 参数
  local dir=$1
  shift
  rm -rf "$dir"
  # MSYS2_ARG_CONV_EXCL：不许 MSYS 把 `--prefix /` 转成 `D:/msys64/`
  MSYS2_ARG_CONV_EXCL='*' "$MESON" setup "$dir" \
    --cross-file "$CROSS_FILE" \
    --prefix / \
    --buildtype release \
    -Ddefault_library=static \
    "$@" || return 1
  MSYS2_ARG_CONV_EXCL='*' "$NINJA" -C "$dir" -j "$CORES" || return 1
  MSYS2_ARG_CONV_EXCL='*' DESTDIR="$DEST" "$NINJA" -C "$dir" install || return 1
  pc_fixup || return 1
}

b_libxml2() {
  cd libxml2
  # OHOS 模拟器上没有 libz.so（musl 把常用库并进了 libc），别把 zlib 拉进 DT_NEEDED
  meson_setup .build -Ddocs=disabled -Dzlib=disabled -Dsax1=enabled
}

b_fribidi() {
  cd fribidi
  meson_setup .build -Dtests=false -Ddocs=false
}

b_freetype() {
  cd freetype
  # zlib 会把 libz.so 拉进 DT_NEEDED，而模拟器上没有这个库（musl 并进 libc）
  meson_setup .build -Dzlib=disabled
}

b_harfbuzz() {
  cd harfbuzz
  meson_setup .build -Dtests=disabled -Ddocs=disabled
}

b_fontconfig() {
  cd fontconfig
  meson_setup .build \
    -Ddoc=disabled -Dtests=disabled -Dcache-build=disabled \
    -Dxml-backend=libxml2 -Ddefault-fonts-dirs=/system/fonts
}

b_lcms() {
  cd lcms
  meson_setup .build -Dtests=disabled
}

b_libass() {
  cd libass
  meson_setup .build \
    -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled \
    -Dfontconfig=enabled
}

# ---------------------------------------------------------------- shaderc
b_shaderc() {
  cd shaderc
  rm -rf .build
  cmake -S . -B .build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$OHOS_NDK_HOME/native/build/cmake/ohos.toolchain.cmake" \
    -DOHOS_ARCH="$ABI" \
    -DOHOS_STL=c++_shared \
    -DCMAKE_INSTALL_PREFIX="$DEST" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SKIP_RPATH=TRUE \
    -DBUILD_SHARED_LIBS=OFF \
    -DSHADERC_SKIP_TESTS=ON \
    -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSHADERC_ENABLE_WERROR_COMPILE=OFF
  cmake --build .build --parallel "$CORES" || return 1
  cmake --install .build || return 1
  # 静态库里 shaderc_combined 才是全集，上游就是把它的 .pc 提成 shaderc.pc
  cd "$DEST/lib/pkgconfig"
  [ -f shaderc_combined.pc ] && mv shaderc_combined.pc shaderc.pc
  [ -f shaderc_shared.pc ] && rm -f shaderc_shared.pc
  true
}

# ---------------------------------------------------------------- libplacebo
b_libplacebo() {
  cd libplacebo
  local args="-Ddemos=false -Dlcms=enabled"
  if [ "$WITH_DOVI" = "1" ]; then args="$args -Ddovi=enabled"; else args="$args -Ddovi=disabled"; fi
  if [ "$WITH_VIDEO" = "1" ]; then
    args="$args -Dvulkan=enabled -Dopengl=enabled -Dshaderc=enabled"
  else
    args="$args -Dvulkan=disabled -Dopengl=disabled -Dshaderc=disabled"
  fi
  # shellcheck disable=SC2086
  meson_setup .build $args
}

# ---------------------------------------------------------------- lua
b_lua() {
  cd lua
  make -j"$CORES" CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
    PLAT=linux LUA_T= LUAC_T= MYCFLAGS="-fPIC -D__MUSL__=1"
  make INSTALL_TOP="$DEST" install
  cat > "$DEST/lib/pkgconfig/lua.pc" <<EOF
Name: Lua
Description: Lua
Version: $V_LUA
Libs: -L\${libdir} -llua
Cflags: -I\${includedir}
prefix=$DEST
libdir=\${prefix}/lib
includedir=\${prefix}/include
EOF
}

# ---------------------------------------------------------------- mpv
b_mpv() {
  cd mpv
  local src
  src=$(pwd -W 2>/dev/null || pwd)
  local build=$src/.build
  local args="-Dlibmpv=true -Dcplayer=false -Dgpl=false -Dbuild-date=false -Dmanpage-build=disabled"
  args="$args -Dohos=enabled -Dopensles=disabled -Dzlib=disabled"
  if [ "$WITH_VIDEO" = "1" ]; then
    args="$args -Degl-ohos=enabled -Dvulkan=enabled -Dgl=enabled -Dshaderc=enabled"
  else
    args="$args -Degl-ohos=disabled -Dvulkan=disabled -Dgl=disabled -Dshaderc=disabled"
  fi
  if [ "$WITH_LUA" = "1" ]; then args="$args -Dlua=enabled"; else args="$args -Dlua=disabled"; fi
  rm -rf "$build"
  # shellcheck disable=SC2086
  MSYS2_ARG_CONV_EXCL='*' "$MESON" setup "$build" "$src" \
    --cross-file "$CROSS_FILE" \
    --prefix / \
    --buildtype release \
    -Ddefault_library=shared \
    -Dstrip=true \
    $args || return 1
  MSYS2_ARG_CONV_EXCL='*' "$NINJA" -C "$build" -j "$CORES" || return 1
  MSYS2_ARG_CONV_EXCL='*' DESTDIR="$DEST/mpv" "$NINJA" -C "$build" install || return 1
  mv "$DEST/mpv/lib/libmpv.so" "$DEST/libmpv.so" || return 1
}

case "${1:-all}" in
  syspc)      step syspc sys_pc ;;
  mbedtls)    step mbedtls b_mbedtls ;;
  ffmpeg)     step ffmpeg b_ffmpeg ;;
  libxml2)    step libxml2 b_libxml2 ;;
  fribidi)    step fribidi b_fribidi ;;
  freetype)   step freetype b_freetype ;;
  harfbuzz)   step harfbuzz b_harfbuzz ;;
  fontconfig) step fontconfig b_fontconfig ;;
  libass)     step libass b_libass ;;
  lcms)       step lcms b_lcms ;;
  shaderc)    step shaderc b_shaderc ;;
  libplacebo) step libplacebo b_libplacebo ;;
  lua)        step lua b_lua ;;
  mpv)        step mpv b_mpv ;;
  all)
    step syspc sys_pc
    step mbedtls b_mbedtls
    step ffmpeg b_ffmpeg
    step libxml2 b_libxml2
    step fribidi b_fribidi
    step freetype b_freetype
    step harfbuzz b_harfbuzz
    step fontconfig b_fontconfig
    step libass b_libass
    step lcms b_lcms
    if [ "$WITH_VIDEO" = "1" ]; then step shaderc b_shaderc; fi
    step libplacebo b_libplacebo
    if [ "$WITH_LUA" = "1" ]; then step lua b_lua; fi
    step mpv b_mpv
    ;;
  *)
    echo "用法：$0 [all|syspc|mbedtls|ffmpeg|libxml2|fribidi|freetype|harfbuzz|fontconfig|libass|lcms|shaderc|libplacebo|lua|mpv]" >&2
    exit 2
    ;;
esac

