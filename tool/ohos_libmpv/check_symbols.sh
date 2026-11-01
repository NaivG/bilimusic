#!/usr/bin/env bash
# 检查 libmpv.so 的未解析符号能否被 DT_NEEDED 里的系统库覆盖
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

SO=$DEST/libmpv.so
READELF=$LLVM_BIN/llvm-readelf.exe
NM=$LLVM_BIN/llvm-nm.exe
TMP=$WORK_DIR/.symcheck
rm -rf "$TMP"; mkdir -p "$TMP"

"$READELF" -d "$SO" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' > "$TMP/needed.txt"

# 未解析符号
"$NM" -D --undefined-only "$SO" | awk '{print $NF}' | sort -u > "$TMP/undef.txt"

# 各 NEEDED 库的导出符号（sysroot 里都有对应 .so）
: > "$TMP/provided.txt"
while read -r lib; do
  # libc++_shared.so 不在 sysroot/usr/lib 里，在 llvm/lib/<triple>/
  f=$SYSROOT/usr/lib/$TRIPLE/$lib
  [ -e "$f" ] || f=$OHOS_NDK_HOME/native/llvm/lib/$TRIPLE/$lib
  [ -e "$f" ] || f=$OHOS_NDK_HOME/native/llvm/lib/$TRIPLE/c++/$lib
  [ -e "$f" ] || { echo "  ! 找不到 $lib（sysroot / llvm 里都没有）"; continue; }
  "$NM" -D --defined-only "$f" | awk '{print $NF}' | sed 's/@.*//' >> "$TMP/provided.txt"
done < "$TMP/needed.txt"
sort -u "$TMP/provided.txt" -o "$TMP/provided.txt"

comm -23 "$TMP/undef.txt" "$TMP/provided.txt" > "$TMP/missing.txt"

echo "未解析符号：$(wc -l < "$TMP/undef.txt")  系统库导出：$(wc -l < "$TMP/provided.txt")  缺：$(wc -l < "$TMP/missing.txt")"
if [ -s "$TMP/missing.txt" ]; then
  echo "--- 前 40 个未被覆盖的符号 ---"
  head -40 "$TMP/missing.txt"
else
  echo "✓ 所有未解析符号都能由 NEEDED 里的系统库提供"
fi
