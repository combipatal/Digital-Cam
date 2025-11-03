import argparse, numpy as np
from PIL import Image
p = argparse.ArgumentParser()
p.add_argument("hexfile")
p.add_argument("--size", default="320x240")
p.add_argument("--out", default="out.png")
args = p.parse_args()

W, H = map(int, args.size.lower().split("x"))
vals = []
with open(args.hexfile, "r", encoding="utf-8", errors="ignore") as f:
    for ln in f:
        s = ln.strip()
        if not s: continue
        for tok in s.replace(",", " ").split():
            vals.append(int(tok, 16))
arr = np.array(vals, dtype=np.int32)
if arr.size != W*H:
    raise SystemExit(f"size mismatch: got {arr.size} values, expected {W*H}")

vmin, vmax = int(arr.min()), int(arr.max())
if 0 <= vmin and vmax <= 255:
    img8 = arr.astype(np.uint8)
else:
    img8 = ((arr - vmin) * 255.0 / (vmax - vmin)).clip(0,255).astype(np.uint8)

Image.fromarray(img8.reshape(H, W), mode="L").save(args.out)
print(f"saved {args.out} ({W}x{H}), range=({vmin},{vmax})")
