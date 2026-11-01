#!/usr/bin/env bash
# 给依赖打上游补丁（目前只有 libplacebo 两个）
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

apply_patches() { # $1=源码目录相对路径 $2=补丁目录
  local dep=$1 dir=$2
  [ -d "$SRC_DIR/$dep" ] || { echo "缺少源码：$SRC_DIR/$dep" >&2; exit 1; }
  for p in "$dir"/*.patch; do
    [ -e "$p" ] || continue
    local name
    name=$(basename "$p")
    if ( cd "$SRC_DIR/$dep" && git apply --reverse --check "$p" ) >/dev/null 2>&1; then
      echo "已应用，跳过：$dep <- $name"
    elif ( cd "$SRC_DIR/$dep" && git apply --check "$p" ) >/dev/null 2>&1; then
      ( cd "$SRC_DIR/$dep" && git apply "$p" )
      echo "已应用：$dep <- $name"
    else
      echo "补丁不适用（上游已改？）：$dep <- $name" >&2
      exit 1
    fi
  done
}

apply_patches libplacebo "$ROOT_DIR/patches/libplacebo"
