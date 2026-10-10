#!/usr/bin/env python3
"""用 Python 的 qrcode 库生成对照矩阵 → scripts/fixtures/qr_matrices.json

verify.mjs 用它逐位比对自己的编码器。分两组：
  auto       —— 全链路（含掩码选择），验证数据编码/纠错/摆放/罚分
  forced     —— 强制掩码 0..7，把「格式信息摆放」与「掩码选择」的失败隔离开，
                出错时能立刻定位是哪一半

用法： PYTHONIOENCODING=utf-8 python extension/scripts/gen_qr_fixtures.py
依赖： python -m pip install qrcode
"""
import json
import pathlib

from qrcode.main import QRCode
from qrcode.constants import ERROR_CORRECT_M
from qrcode.util import QRData, MODE_8BIT_BYTE

# 覆盖：短内容(自动落到 v1) / ASCII / 中文 UTF-8 / 真实形态的 TV 登录 URL / 跨版本长内容
SAMPLES = [
    "abc",
    "HELLO WORLD",
    "哔哩哔哩",
    "https://passport.bilibili.com/x/passport-tv-login/qrcode/exchange?auth_code=5f1c9e2a-77d4-4b0e-9f3a-1c2d3e4f5a6b",
    "BiliMusic " * 22,  # 约 200 字节，跨到更高的版本
]

# 只对最短的样本强制 8 个掩码：它落在 v1（21×21），矩阵小，JSON 不会膨胀
FORCED_SAMPLE = SAMPLES[0]


def build(text, mask_pattern=None):
    qr = QRCode(error_correction=ERROR_CORRECT_M, border=0, mask_pattern=mask_pattern)
    qr.add_data(QRData(text.encode("utf-8"), mode=MODE_8BIT_BYTE, check_data=False))
    qr.best_fit()
    # make() 选完掩码不回写 mask_pattern（会一直是 None），这里显式选一次
    chosen = qr.best_mask_pattern() if mask_pattern is None else mask_pattern
    qr.makeImpl(False, chosen)
    return {
        "version": qr.version,
        "mask": chosen,
        "rows": ["".join("1" if cell else "0" for cell in row) for row in qr.modules],
    }


def main():
    fixtures = {"auto": [], "forced": []}
    for text in SAMPLES:
        entry = {"text": text}
        entry.update(build(text))
        fixtures["auto"].append(entry)

    for mask in range(8):
        entry = {"text": FORCED_SAMPLE, "mask_requested": mask}
        entry.update(build(FORCED_SAMPLE, mask_pattern=mask))
        fixtures["forced"].append(entry)

    out = pathlib.Path(__file__).with_name("fixtures") / "qr_matrices.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(fixtures, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    for e in fixtures["auto"]:
        print(f"  auto  v{e['version']} mask={e['mask']} {e['text'][:40]!r}")
    print(f"  forced: {len(fixtures['forced'])} masks x {FORCED_SAMPLE!r}")


if __name__ == "__main__":
    main()
