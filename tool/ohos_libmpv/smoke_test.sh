#!/usr/bin/env bash
# 在模拟器/真机上跑 libmpv 冒烟测试：
#   编译 smoke_test.c → 生成 3 秒正弦 wav → 推到设备 → 加载 libmpv.so 播放
#
#   HDC=D:/.../hdc.exe ./smoke_test.sh
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

HDC=${HDC:-"C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"}
DEV_DIR=/data/local/tmp/libmpv_smoke
SO=$DEST/libmpv.so

[ -f "$SO" ] || { echo "缺少 $SO，先跑 build.sh" >&2; exit 1; }

echo "── 编译冒烟测试程序（$TRIPLE）"
"$LLVM_BIN/clang.exe" --target="$TRIPLE" --sysroot="$SYSROOT" -O2 \
  -o "$WORK_DIR/smoke_test" "$ROOT_DIR/smoke_test.c" \
  -I"$DEST/mpv/include" -L"$DEST" -lmpv -Wl,-rpath,"$DEV_DIR"

echo "── 生成 3 秒 440Hz 正弦 wav"
python3 - "$WORK_DIR/test.wav" <<'PY'
import math, struct, sys, wave
path = sys.argv[1]
rate = 44100
with wave.open(path, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(rate)
    frames = bytearray()
    for i in range(rate * 3):
        v = int(12000 * math.sin(2 * math.pi * 440 * i / rate))
        frames += struct.pack("<hh", v, v)
    w.writeframes(bytes(frames))
print("wav:", path)
PY

# hdc 是原生程序：MSYS 会把参数里的 POSIX 路径转成 Windows 路径（设备的
# `/data/local/tmp/...` 会被转成 `D:\msys64\data\...`）。所以调用 hdc 时一律关掉
# 参数转换，本地文件用「先 cd 到暂存目录 + 裸文件名」的方式传。
echo "── 推送到设备 $DEV_DIR"
MSYS2_ARG_CONV_EXCL='*' "$HDC" shell "rm -rf $DEV_DIR; mkdir -p $DEV_DIR" >/dev/null
STAGE=$WORK_DIR/smoke-stage
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$SO" "$WORK_DIR/smoke_test" "$WORK_DIR/test.wav" "$STAGE/"
(
  cd "$STAGE"
  for f in libmpv.so smoke_test test.wav; do
    MSYS2_ARG_CONV_EXCL='*' "$HDC" file send "$f" "$DEV_DIR/" | tail -1
  done
)

echo "── 运行"
MSYS2_ARG_CONV_EXCL='*' "$HDC" shell "chmod +x $DEV_DIR/smoke_test; cd $DEV_DIR && LD_LIBRARY_PATH=$DEV_DIR ./smoke_test $DEV_DIR/test.wav"
