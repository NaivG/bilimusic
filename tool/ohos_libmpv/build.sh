#!/usr/bin/env bash
# libmpv for OpenHarmony：一键构建入口
#
#   ARCH=x86_64 ./build.sh              # 模拟器 x64（默认）
#   ARCH=aarch64 ./build.sh             # 真机 arm64
#   WORK_DIR=E:/libmpv ./build.sh       # 指定源码/产物落点
#
# 产物：$WORK_DIR/$ARCH-build/libmpv.so
set -eu
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W 2>/dev/null || pwd)
export ROOT_DIR
# shellcheck source=./env.sh
. "$ROOT_DIR/env.sh"

step_fetch()  { bash "$ROOT_DIR/fetch.sh"; }
step_patch()  { bash "$ROOT_DIR/patch.sh"; }
step_deps()   { bash "$ROOT_DIR/deps.sh" all; }
step_verify() { bash "$ROOT_DIR/verify.sh"; }
step_smoke()  { bash "$ROOT_DIR/smoke_test.sh"; }

echo "═══ libmpv for OpenHarmony ($ARCH -> $TRIPLE) ═══"
echo "SDK      : $OHOS_NDK_HOME"
echo "源码目录 : $SRC_DIR"
echo "安装前缀 : $DEST"

case ${1:-all} in
  fetch)  step_fetch ;;
  patch)  step_patch ;;
  deps)   step_deps ;;
  verify) step_verify ;;
  smoke)  step_smoke ;;
  all)
    step_fetch
    step_patch
    step_deps
    step_verify
    ;;
  *)
    echo "用法：$0 [all|fetch|patch|deps|verify|smoke]" >&2
    exit 2
    ;;
esac
