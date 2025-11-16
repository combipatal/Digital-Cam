
import argparse
import os
import sys
import cv2
import numpy as np

def pack_rgb565(rgb):
    # rgb: HxWx3, uint8, RGB order
    r = (rgb[...,0] >> 3).astype(np.uint16)  # 5 bits
    g = (rgb[...,1] >> 2).astype(np.uint16)  # 6 bits
    b = (rgb[...,2] >> 3).astype(np.uint16)  # 5 bits
    packed = (r << 11) | (g << 5) | b       # 16-bit RGB565
    return packed

def pack_rgb888(rgb):
    # Return uint32 with RRGGBB in the lower 24 bits
    r = rgb[...,0].astype(np.uint32)
    g = rgb[...,1].astype(np.uint32)
    b = rgb[...,2].astype(np.uint32)
    return (r << 16) | (g << 8) | b

def to_gray8(rgb):
    # standard luma transform
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    return gray.astype(np.uint8)

def write_hex_lines(arr, out_path, width, height, prefix='0x', little_endian=False, bytes_per_pixel=None):
    """
    arr: 2D (gray) or 2D of packed integer values (RGB565 or RGB888)
    Writes one pixel per line in row-major order, y from 0..H-1, x from 0..W-1.
    """
    with open(out_path, 'w', newline='\n') as f:
        if arr.ndim == 2:
            # grayscale or packed 16-bit/24-bit stored as 2D ints
            flat = arr.reshape(-1)
            for v in flat:
                if bytes_per_pixel == 1:  # GRAY8
                    s = f"{int(v):02X}"
                elif bytes_per_pixel == 2:  # RGB565
                    v = int(v) & 0xFFFF
                    if little_endian:
                        lo = v & 0xFF
                        hi = (v >> 8) & 0xFF
                        s = f"{lo:02X}{hi:02X}"
                    else:
                        s = f"{v:04X}"
                elif bytes_per_pixel == 3:  # RGB888
                    v = int(v) & 0xFFFFFF
                    if little_endian:
                        # little-endian byte order: BB GG RR
                        b =  v        & 0xFF
                        g = (v >> 8)  & 0xFF
                        r = (v >> 16) & 0xFF
                        s = f"{b:02X}{g:02X}{r:02X}"
                    else:
                        s = f"{v:06X}"  # RR GG BB
                else:
                    s = f"{int(v):X}"
                f.write(f"{prefix}{s}\n" if prefix else f"{s}\n")
        else:
            raise ValueError("Unsupported array ndim")

def parse_size(s):
    if 'x' in s.lower():
        w,h = s.lower().split('x')
        return int(w), int(h)
    raise argparse.ArgumentError(None, "Size must be like 320x240")

def main():
    ap = argparse.ArgumentParser(description="Convert image to HEX lines for FPGA testbench.")
    ap.add_argument("input", help="Input image path (any format OpenCV supports)")
    ap.add_argument("--fmt", choices=["rgb565","rgb888","gray8"], default="rgb565",
                    help="Output pixel format (default: rgb565)")
    ap.add_argument("--size", default="320x240", help="Output size WxH (default: 320x240)")
    ap.add_argument("--out", required=True, help="Output .hex path")
    ap.add_argument("--no-0x", action="store_true", help="Do not prefix lines with 0x")
    ap.add_argument("--little-endian", action="store_true", help="Write bytes little-endian (rgb565/rgb888)")
    args = ap.parse_args()

    w,h = parse_size(args.size)

    img = cv2.imread(args.input, cv2.IMREAD_COLOR)
    if img is None:
        print(f"ERROR: failed to read image: {args.input}", file=sys.stderr)
        sys.exit(1)

    # Resize to requested size if different
    if img.shape[1] != w or img.shape[0] != h:
        img = cv2.resize(img, (w,h), interpolation=cv2.INTER_AREA)

    # BGR -> RGB
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    prefix = "" if args.no_0x else "0x"

    if args.fmt == "rgb565":
        packed = pack_rgb565(rgb).astype(np.uint16)
        write_hex_lines(packed, args.out, w, h, prefix=prefix, little_endian=args.little_endian, bytes_per_pixel=2)
    elif args.fmt == "rgb888":
        packed = pack_rgb888(rgb).astype(np.uint32)
        write_hex_lines(packed, args.out, w, h, prefix=prefix, little_endian=args.little_endian, bytes_per_pixel=3)
    else:  # gray8
        gray = to_gray8(rgb)
        write_hex_lines(gray, args.out, w, h, prefix=prefix, little_endian=False, bytes_per_pixel=1)

    print(f"OK: wrote {args.out} ({w}x{h}, fmt={args.fmt})")

if __name__ == "__main__":
    main()
