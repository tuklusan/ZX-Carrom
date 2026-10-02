#!/usr/bin/env python3
"""Generate tables.asm for Carrom Arena ZX: the static board screen, pre-shifted
sprites, robot figures, maths tables and formation/placement tables."""
import math, os

HERE = os.path.dirname(os.path.abspath(__file__))
out = []

def db(label, data, per=16):
    out.append(f"{label}:")
    for i in range(0, len(data), per):
        out.append("    db " + ",".join(str(b & 255) for b in data[i:i + per]))

def dw(label, data, per=12):
    out.append(f"{label}:")
    for i in range(0, len(data), per):
        out.append("    dw " + ",".join(str(w & 0xFFFF) for w in data[i:i + per]))

# ---------------------------------------------------------------- geometry
PX0, PY0, PSIZE = 56, 24, 144          # play area (inside the cushion)
CX, CY = 128, 96                       # board centre
POCKETS = [(60, 28), (196, 28), (60, 164), (196, 164)]
BASE = 66                              # baseline distance from centre
BASE_HALF = 56                         # striker slides centre +-56

# ---------------------------------------------------------------- screen helpers
def scr_addr(x, y):
    return 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3)

pix = [[0] * 256 for _ in range(192)]
attr = [[0x07] * 32 for _ in range(24)]

def pset(x, y, v=1):
    if 0 <= x < 256 and 0 <= y < 192:
        pix[y][x] = v

def setattr_rect(c0, r0, c1, r1, a):
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            attr[r][c] = a

# ---------------------------------------------------------------- attributes
A_PLAY, A_WOOD, A_POCKET = 0x0F, 0x32, 0x01
A_RED, A_CYAN = 0x42, 0x45
setattr_rect(0, 0, 31, 0, 0x47)            # title
setattr_rect(6, 2, 25, 21, A_WOOD)         # frame
setattr_rect(7, 3, 24, 20, A_PLAY)         # play surface
for c, r in ((7, 3), (24, 3), (7, 20), (24, 20)):
    attr[r][c] = A_POCKET
setattr_rect(0, 1, 5, 2, A_RED); setattr_rect(0, 21, 5, 22, A_RED)
setattr_rect(26, 1, 31, 2, A_CYAN); setattr_rect(26, 21, 31, 22, A_CYAN)
setattr_rect(6, 1, 25, 1, A_RED); setattr_rect(6, 22, 25, 22, A_RED)
setattr_rect(5, 3, 5, 20, A_CYAN); setattr_rect(26, 3, 26, 20, A_CYAN)
setattr_rect(0, 23, 31, 23, 0x46)

# ---------------------------------------------------------------- wood frame
for y in range(16, 184):
    for x in range(48, 208):
        inplay = PX0 <= x < PX0 + PSIZE and PY0 <= y < PY0 + PSIZE
        if inplay:
            continue
        top_or_bottom = y < PY0 or y >= PY0 + PSIZE
        if top_or_bottom:
            grain = ((y * 3 + (x // 23) * 2) % 5 == 0) and ((x + y * 7) % 13 != 0)
        else:
            grain = ((x * 3 + (y // 23) * 2) % 5 == 0) and ((y + x * 7) % 13 != 0)
        if grain:
            pset(x, y)
# inner edge of the cushion
for x in range(PX0 - 1, PX0 + PSIZE + 1):
    pset(x, PY0 - 1); pset(x, PY0 + PSIZE)
for y in range(PY0 - 1, PY0 + PSIZE + 1):
    pset(PX0 - 1, y); pset(PX0 + PSIZE, y)
# outer edge
for x in range(48, 208):
    pset(x, 16); pset(x, 183)
for y in range(16, 184):
    pset(48, y); pset(207, y)

# ---------------------------------------------------------------- markings
def circle(cx, cy, r, dotted=1):
    n = max(24, int(2 * math.pi * r * 1.5))
    for i in range(n):
        if dotted > 1 and (i // 2) % dotted:
            continue
        a = 2 * math.pi * i / n
        pset(int(round(cx + r * math.cos(a))), int(round(cy + r * math.sin(a))))

circle(CX - 0.5, CY - 0.5, 12)            # centre circle
circle(CX - 0.5, CY - 0.5, 29, dotted=2)  # outer circle
circle(CX - 0.5, CY - 0.5, 3)             # centre spot
# baselines: two lines with a circle at each end (classic carrom)
for s in range(4):
    for t in range(-BASE_HALF, BASE_HALF + 1):
        for off in (-5, 5):
            u, v = t, -BASE + off
            if s == 0:   x, y = CX + u, CY + v
            elif s == 2: x, y = CX + u, CY - v
            elif s == 1: x, y = CX - v, CY + u
            else:        x, y = CX + v, CY + u
            if abs(t) < BASE_HALF - 4:
                pset(int(x), int(y))
    for t in (-BASE_HALF, BASE_HALF):
        u, v = t, -BASE
        if s == 0:   x, y = CX + u, CY + v
        elif s == 2: x, y = CX + u, CY - v
        elif s == 1: x, y = CX - v, CY + u
        else:        x, y = CX + v, CY + u
        circle(x, y, 5)
# corner arrows (dotted diagonals from the pockets toward the centre)
for (px, py) in POCKETS:
    dx = 1 if px < CX else -1
    dy = 1 if py < CY else -1
    for k in range(12, 44):
        if k % 3 != 2:
            pset(px + dx * k, py + dy * k)
    for k in range(4):   # arrowhead at the inner end, pointing to the pocket
        pset(px + dx * (13 + k), py + dy * 13)
        pset(px + dx * 13, py + dy * (13 + k))
# pockets: black disc (paper) with blue ink around it inside the corner cell
for (px, py) in POCKETS:
    cx0 = (px // 8) * 8; cy0 = (py // 8) * 8
    for y in range(cy0, cy0 + 8):
        for x in range(cx0, cx0 + 8):
            d = math.hypot(x + 0.5 - px, y + 0.5 - py)
            pset(x, y, 0 if d <= 4.6 else 1)

# ---------------------------------------------------------------- stars in the margins
import random
rnd = random.Random(1982)
for _ in range(70):
    side = rnd.randrange(2)
    x = rnd.randrange(0, 38) if side == 0 else rnd.randrange(218, 256)
    y = rnd.randrange(26, 166)
    pset(x, y)
    if rnd.random() < 0.15:
        pset(x + 1, y); pset(x - 1, y); pset(x, y + 1); pset(x, y - 1)

# ---------------------------------------------------------------- title, from the ROM font
rom = open(os.path.join(os.path.dirname(__import__('skoolkit').__file__), 'resources', '48.rom'), 'rb').read()
def text(col, row, s):
    for i, ch in enumerate(s):
        g = rom[0x3D00 + (ord(ch) - 32) * 8: 0x3D00 + (ord(ch) - 32) * 8 + 8]
        for yy in range(8):
            for xx in range(8):
                pset((col + i) * 8 + xx, row * 8 + yy, (g[yy] >> (7 - xx)) & 1)
title = "SANYALnet Labs  Carrom Arena"
text((32 - len(title)) // 2, 0, title)

screen = bytearray(6912)
for y in range(192):
    for xb in range(32):
        b = 0
        for k in range(8):
            b = (b << 1) | pix[y][xb * 8 + k]
        screen[scr_addr(xb * 8, y) - 0x4000] = b
for r in range(24):
    for c in range(32):
        screen[6144 + r * 32 + c] = attr[r][c]
def rle(data):
    """n<128: n literal bytes follow; n>=128: next byte repeated n-126 times; 0 ends"""
    res, i, lit = [], 0, []
    def flush():
        while lit:
            chunk = lit[:127]; del lit[:127]
            res.extend([len(chunk)] + chunk)
    while i < len(data):
        j = i
        while j < len(data) and data[j] == data[i] and j - i < 129:
            j += 1
        if j - i >= 3:
            flush(); res.extend([128 + (j - i) - 2, data[i]]); i = j
        else:
            lit.append(data[i]); i += 1
    flush(); res.append(0)
    return res
packed = rle(list(screen))
db("BOARD_RLE", packed, 32)
print("board screen packed to", len(packed), "bytes")

# ---------------------------------------------------------------- sprites (mask/data, pre-shifted)
COIN_W = ["..XXXX..", ".XXXXXX.", "XXXXXXXX", "XXX.XXXX", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", "..XXXX.."]
COIN_B = ["..XXXX..", ".X....X.", "X......X", "X......X", "X......X", "X......X", ".X....X.", "..XXXX.."]
QUEEN  = ["..XXXX..", ".XXXXXX.", "XXX..XXX", "XX....XX", "XX....XX", "XXX..XXX", ".XXXXXX.", "..XXXX.."]
DISC8  = COIN_W[:3] + ["XXXXXXXX"] + COIN_W[4:]
STRIKER = ["...XXXX...", ".XX....XX.", ".X......X.", "X...XX...X", "X..X..X..X",
           "X..X..X..X", "X...XX...X", ".X......X.", ".XX....XX.", "...XXXX..."]
DISC10 = ["...XXXX...", ".XXXXXXXX.", ".XXXXXXXX.", "XXXXXXXXXX", "XXXXXXXXXX",
          "XXXXXXXXXX", "XXXXXXXXXX", ".XXXXXXXX.", ".XXXXXXXX.", "...XXXX..."]

def preshift(shape, footprint, wbytes):
    blk = []
    for sh in range(8):
        for row, frow in zip(shape, footprint):
            d = 0; m = 0
            for ch in row: d = (d << 1) | (ch == 'X')
            for ch in frow: m = (m << 1) | (ch == 'X')
            n = len(row)
            d <<= (wbytes * 8 - n - sh); m <<= (wbytes * 8 - n - sh)
            mask = ~m & ((1 << (wbytes * 8)) - 1)
            for k in range(wbytes - 1, -1, -1):
                blk.append((mask >> (8 * k)) & 255)
                blk.append((d >> (8 * k)) & 255)
    return blk
db("SPR_WHITE", preshift(COIN_W, DISC8, 2))
db("SPR_BLACK", preshift(COIN_B, DISC8, 2))
db("SPR_QUEEN", preshift(QUEEN, DISC8, 2))
db("SPR_STRIKER", preshift(STRIKER, DISC10, 3))

# ---------------------------------------------------------------- robots
ROBOT_N = [  # 16x8, faces down (toward the board)
    "...XXXXXXXXXX...",
    "..X..........X..",
    "..X.XX....XX.X..",
    "XXX.XX....XX.XXX",
    "X.X....XX....X.X",
    "X.X.XXXXXXXX.X.X",
    "..XXXXXXXXXXXX..",
    ".....X....X.....",
]
ROBOT_S = list(reversed(ROBOT_N))
def rot_w(rows):   # 8x16: faces right (toward the board)
    return ["".join(rows[7 - c][r] for c in range(8)) for r in range(16)]
ROBOT_W = rot_w(ROBOT_N)
ROBOT_W = ["".join(reversed(r)) for r in ["".join(ROBOT_N[c][r] for c in range(8)) for r in range(16)]]
ROBOT_E = ["".join(reversed(r)) for r in ROBOT_W]
def bits(rows):
    res = []
    for row in rows:
        v = 0
        for ch in row: v = (v << 1) | (ch == 'X')
        n = len(row)
        for k in range(n // 8 - 1, -1, -1):
            res.append((v >> (8 * k)) & 255)
    return res
db("ROB_N", bits(ROBOT_N)); db("ROB_S", bits(ROBOT_S))
db("ROB_W", bits(ROBOT_E)); db("ROB_E", bits(ROBOT_W))

# ---------------------------------------------------------------- UDG glyphs (chars 128..)
HUD_B = ["..XXXX..", ".X....X.", "X......X", "X..XX..X", "X..XX..X", "X......X", ".X....X.", "..XXXX.."]
db("UDG", bits(COIN_W) + bits(HUD_B) + bits(QUEEN))

# ---------------------------------------------------------------- maths tables
out.append("    align 256")
dw("QSQ", [n * n // 4 for n in range(512)])
out.append("    align 256")
db("ROWLO", [scr_addr(0, y) & 255 for y in range(192)])
out.append("    align 256")
db("ROWHI", [scr_addr(0, y) >> 8 for y in range(192)])
# halo ring offsets (radius 8) for the placement pulse, terminated by 128
halo = sorted({(int(round(8 * math.cos(a))), int(round(8 * math.sin(a))))
               for a in [2 * math.pi * i / 64 for i in range(64)]})
db("HALO", [v for p in halo for v in p] + [128, 128])

# formation: 24 rotations x 18 coins, offsets in 8.8 pixels (ids 0-8 white, 9-17 black)
R = 4.25
form = []
for rot in range(24):
    th = rot * math.pi / 12
    whites, blacks = [], []
    for i in range(6):
        a = th + i * math.pi / 3
        (whites if i % 2 == 0 else blacks).append((2 * R * math.cos(a), 2 * R * math.sin(a)))
    for i in range(6):
        a = th + i * math.pi / 3
        whites.append((4 * R * math.cos(a), 4 * R * math.sin(a)))
    for i in range(6):
        a = th + i * math.pi / 3 + math.pi / 6
        blacks.append((2 * math.sqrt(3) * R * math.cos(a), 2 * math.sqrt(3) * R * math.sin(a)))
    for (x, y) in whites + blacks:
        form += [int(round(x * 256)), int(round(y * 256))]
dw("FORMATION", form)

# free spots nearest the centre (queen / returned coins), signed byte pairs
spots = set()
for r in [0] + list(range(9, 60, 3)):
    n = 1 if r == 0 else max(6, int(2 * math.pi * r / 4))
    for i in range(n):
        a = 2 * math.pi * i / n + (0.3 if (r // 3) % 2 else 0)
        spots.add((int(round(r * math.cos(a))), int(round(r * math.sin(a)))))
spots = sorted(spots, key=lambda p: (p[0] ** 2 + p[1] ** 2, p))
spots = [p for p in spots if abs(p[0]) < 62 and abs(p[1]) < 62][:240]
db("FREESPOTS", [v for p in spots for v in p] + [128, 128])

# due spots: inside the outer circle, clear of the centre circle, farthest from every pocket first
due = set()
for r in range(17, 28, 2):
    n = int(2 * math.pi * r / 3)
    for i in range(n):
        a = 2 * math.pi * i / n
        due.add((int(round(r * math.cos(a))), int(round(r * math.sin(a)))))
def pocket_dist(p):
    return min(math.hypot(p[0] + CX - px, p[1] + CY - py) for px, py in POCKETS)
due = sorted(due, key=lambda p: (-pocket_dist(p), p))[:120]
db("DUESPOTS", [v for p in due for v in p] + [128, 128])

open(os.path.join(HERE, "tables.asm"), "w").write("\n".join(out) + "\n")
print("tables.asm written,", len(spots), "free spots,", len(due), "due spots")
