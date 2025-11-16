import argparse
import numpy as np
from PIL import Image

# 인자 설정 (기존 구조 그대로)
p = argparse.ArgumentParser()
p.add_argument("hexfile")
p.add_argument("--size", default="320x240")
p.add_argument("--out", default="out_rgb565.png")
args = p.parse_args()

W, H = map(int, args.size.lower().split("x"))

# HEX 파일 읽기
vals = []
with open(args.hexfile, "r", encoding="utf-8", errors="ignore") as f:
    for ln in f:
        s = ln.strip()
        if not s:
            continue
        for tok in s.replace(",", " ").split():
            vals.append(int(tok, 16))

arr = np.array(vals, dtype=np.uint16)
if arr.size != W * H:
    raise SystemExit(f"size mismatch: got {arr.size} values, expected {W*H}")

# RGB565 → RGB888 변환
r = ((arr >> 11) & 0x1F) << 3
g = ((arr >> 5) & 0x3F) << 2
b = (arr & 0x1F) << 3

rgb = np.dstack([r, g, b]).astype(np.uint8)
img = Image.fromarray(rgb.reshape(H, W, 3), "RGB")
img.save(args.out)

print(f"Saved {args.out} ({W}x{H}) RGB565 → RGB888 변환 완료, 총 {arr.size} 픽셀")
