#!/usr/bin/env python3
"""从 Python 的 qrcode 库导出 QR 参数表 → src/core/qr_tables.js

转录这种 40 行 × 6 列的表，错一个数整张码就扫不出来，而错法还极其隐蔽
（结构看着完全正常，只是扫不出内容）。所以表必须由参照实现生成，不手写。

用法： python extension/scripts/gen_qr_tables.py > extension/src/core/qr_tables.js
依赖： python -m pip install qrcode
"""
from qrcode.base import rs_blocks
from qrcode.constants import ERROR_CORRECT_M
from qrcode.util import PATTERN_POSITION_TABLE, G15, G15_MASK


def compact(blocks):
    """[(total, data), ...] → [t1, d1, c1, t2, d2, c2]
    同一 (total, data) 的相邻块合并计数；QR 规范里同一版本最多两种分块。"""
    groups = []
    for b in blocks:
        key = (b.total_count, b.data_count)
        if groups and groups[-1][0] == key:
            groups[-1][1] += 1
        else:
            groups.append([key, 1])
    flat = []
    for (total, data), count in groups:
        flat += [total, data, count]
    while len(flat) < 6:
        flat.append(0)
    return flat


print("""/**
 * QR 编码参数表（纠错块结构 + 校正图形位置）
 *
 * 由 Python 的 `qrcode` 库导出（scripts/gen_qr_tables.py），**不要手改**。
 *
 * 纠错级别固定 **M**（屏幕扫码的通用默认，15% 恢复能力）——因此每个版本只留
 * 一组 (total, data, count)，不用背 L/M/Q/H 四套。
 *
 * RS_BLOCKS[version] = [total1, data1, count1, total2, data2, count2]
 *   total = 该分块的总码字数，data = 数据码字数，count = 这种分块有几块。
 *   纠错码字数 = total - data；同一版本里各块按 count 展开后依次排列。
 *
 * PATTERN_POSITION[version] = 校正图形中心坐标（版本 1 没有校正图形）。
 */
export const RS_BLOCKS = [""")
print("  null,  // 版本号从 1 开始，0 号占位")
for v in range(1, 41):
    print(f"  {compact(rs_blocks(v, ERROR_CORRECT_M))},  // v{v}")
print("]")
print()
print(f"export const FORMAT_MASK = 0x{G15_MASK:04x}  // 格式信息异或掩码")
print(f"export const FORMAT_GEN = 0x{G15:04x}        // BCH(15,5) 生成多项式")
print()
print("export const PATTERN_POSITION = [")
print("  [],  // v1 无校正图形")
for i, p in enumerate(PATTERN_POSITION_TABLE[1:], start=2):
    print(f"  {list(p)},  // v{i}")
print("]")
