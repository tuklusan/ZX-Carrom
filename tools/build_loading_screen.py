#!/usr/bin/env python3
# Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
# Licensed under the SANYALnet Labs Non-Commercial License.
"""Generate the deterministic 6912-byte loading screen."""
from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
sys.path.insert(0, str(SRC))
import font64

def pixoff(x, y):
    return ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3)

def make_screen():
    s = bytearray(6912)
    glyphs = font64.build()

    def pset(x, y):
        if 0 <= x < 256 and 0 <= y < 192:
            s[pixoff(x, y)] |= 0x80 >> (x & 7)

    def hline(x0, x1, y):
        for x in range(x0, x1 + 1):
            pset(x, y)

    def vline(x, y0, y1):
        for yy in range(y0, y1 + 1):
            pset(x, yy)

    def box(x0, y0, x1, y1):
        hline(x0, x1, y0)
        hline(x0, x1, y1)
        vline(x0, y0, y1)
        vline(x1, y0, y1)

    def ring(cx, cy, r):
        rr = r * r
        for y in range(cy - r - 1, cy + r + 2):
            for x in range(cx - r - 1, cx + r + 2):
                d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
                if rr - r <= d <= rr + r:
                    pset(x, y)

    def text(x, y, msg, scale=1):
        for ch in msg:
            code = ord(ch)
            if not 32 <= code < 128:
                code = 32
            g = glyphs[(code - 32) * 8:(code - 31) * 8]
            for gy, row in enumerate(g):
                for gx in range(3):
                    if row & (0x80 >> gx):
                        for yy in range(scale):
                            for xx in range(scale):
                                pset(x + gx * scale + xx, y + gy * scale + yy)
            x += 4 * scale

    def centre(y, msg, scale=1):
        text((256 - len(msg) * 4 * scale) // 2, y, msg, scale)

    box(3, 3, 252, 188)
    centre(8, "CARROM ARENA", 2)
    centre(28, "ZX SPECTRUM 48K")
    centre(38, "FOUR ROBOTS - DOUBLES CARROM")

    box(77, 50, 178, 128)
    box(83, 56, 172, 122)
    for cx, cy in ((84, 57), (171, 57), (84, 121), (171, 121)):
        ring(cx, cy, 6)
    ring(128, 89, 12)
    ring(128, 89, 3)
    hline(100, 156, 89)
    vline(128, 70, 108)

    for x, y in ((112, 78), (122, 82), (133, 79), (116, 92), (128, 89), (138, 94), (124, 100)):
        ring(x, y, 2)

    centre(136, "LOADING MATCH...")
    text(12, 146, "SPACE PAUSE/RESUME")
    text(156, 146, "F FAST/NORMAL")
    text(12, 158, "M SOUND MODE")
    text(156, 158, "R NEW MATCH")
    centre(174, "Q QUIT TO BASIC")

    for i in range(4):
        yy = 80 + i * 8
        for y in range(yy, yy + 8):
            for x in range(248, 252):
                pset(x, y)

    attrs = [
        (0, 3, 0x4F),
        (3, 17, 0x47),
        (17, 24, 0x46),
    ]
    for y0, y1, attr in attrs:
        for row in range(y0, y1):
            for col in range(32):
                s[6144 + row * 32 + col] = attr
    for row in range(6, 17):
        for col in range(9, 23):
            s[6144 + row * 32 + col] = 0x45
    for i, ink in enumerate((2, 6, 4, 5)):
        s[6144 + (10 + i) * 32 + 31] = 0x40 | ink

    return bytes(s)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output", nargs="?", default=str(ROOT / "build" / "loading.scr"))
    a = ap.parse_args()
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    data = make_screen()
    out.write_bytes(data)
    print(f"{out}: {len(data)} bytes")

if __name__ == "__main__":
    main()
