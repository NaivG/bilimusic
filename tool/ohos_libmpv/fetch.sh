#!/usr/bin/env bash
# 拉取 libmpv 全部依赖源码到 $SRC_DIR（已存在则跳过，可重复执行）
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. "$ROOT_DIR/versions.sh"

cd "$SRC_DIR"

say() { printf '\n=== %s ===\n' "$1"; }

# git 浅克隆：已有目录直接跳过
clone() { # $1=目录 $2=版本 $3=仓库地址 [--recursive]
  local dir=$1 rev=$2 url=$3 extra=${4:-}
  if [ -d "$dir/.git" ]; then
    echo "已存在，跳过：$dir"
    return 0
  fi
  say "clone $dir ($rev)"
  # shellcheck disable=SC2086
  git -c advice.detachedHead=false clone -q --depth 1 -b "$rev" $extra "$url" "$dir"
}

# 源码包解压（wget → tar）
fetch_tar() { # $1=目录 $2=下载地址 $3=压缩包名 $4=tar 解压参数
  local dir=$1 url=$2 file=$3 flags=$4
  if [ -d "$dir" ]; then
    echo "已存在，跳过：$dir"
    return 0
  fi
  say "download $file"
  wget -q --show-progress -O "$file" "$url"
  mkdir -p "$dir"
  # shellcheck disable=SC2086
  tar -C "$dir" --strip-components=1 $flags "$file"
  rm -f "$file"
}

fetch_tar mbedtls \
  "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$V_MBEDTLS/mbedtls-$V_MBEDTLS.tar.bz2" \
  mbedtls.tar.bz2 -jxf

clone libxml2 "$V_LIBXML2" https://gitlab.gnome.org/GNOME/libxml2.git --recursive
clone fribidi "$V_FRIBIDI" https://github.com/fribidi/fribidi.git
clone freetype "$V_FREETYPE" https://gitlab.freedesktop.org/freetype/freetype.git
clone harfbuzz "$V_HARFBUZZ" https://github.com/harfbuzz/harfbuzz.git
clone fontconfig "$V_FONTCONFIG" https://gitlab.freedesktop.org/fontconfig/fontconfig.git
clone lcms "$V_LCMS" https://github.com/mm2/Little-CMS.git
clone shaderc "$V_SHADERC" https://github.com/google/shaderc.git
clone libass "$V_LIBASS" https://github.com/libass/libass.git
clone libplacebo "$V_LIBPLACEBO" https://code.videolan.org/videolan/libplacebo.git --recursive
clone ffmpeg "$V_FFMPEG" https://code.ffmpeg.org/ErBWs/FFmpeg.git
clone mpv "$V_MPV" https://github.com/ErBWs/mpv.git

fetch_tar lua "https://www.lua.org/ftp/lua-$V_LUA.tar.gz" lua.tar.gz -zxf

# shaderc 的第三方依赖（glslang / SPIRV-Tools / SPIRV-Headers）
if [ -d shaderc ] && [ ! -d shaderc/third_party/glslang ]; then
  say "shaderc/utils/git-sync-deps"
  ( cd shaderc && python3 ./utils/git-sync-deps )
fi

# 需要本地构建的组件（x86_64 不需要）：dav1d / dovi_tools
if [ "${WITH_DAV1D:-0}" = "1" ]; then
  clone dav1d "$V_DAV1D" https://code.videolan.org/videolan/dav1d.git
fi
if [ "${WITH_DOVI:-0}" = "1" ]; then
  clone dovi_tools "$V_DOVI_TOOLS" https://github.com/quietvoid/dovi_tool.git
fi

say "源码就绪"
du -sh . 2>/dev/null || true
