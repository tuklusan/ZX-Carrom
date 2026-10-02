#!/usr/bin/env python3
"""Independently parse and validate the accepted Carrom Arena fast TZX."""
from pathlib import Path
import argparse, collections, struct

ROM_PILOTS = [512, 512]
FAST_LEADER = 256
FAST_LEADER_PULSE = 1710
ZERO = 855
ONE = 1710
BYTE_DELAY = 64


def u16(d, o): return struct.unpack_from('<H', d, o)[0]
def u24(d, o): return int.from_bytes(d[o:o+3], 'little')
def u32(d, o): return struct.unpack_from('<I', d, o)[0]


def validate(path):
    d = Path(path).read_bytes()
    if d[:8] != b'ZXTape!\x1a' or len(d) < 10:
        raise SystemExit(f"{path}: bad TZX header")
    o = 10
    ids, rom, pulses, explicit_pauses, per_block_pauses = [], [], [], [], []
    while o < len(d):
        bid = d[o]; o += 1; ids.append(bid)
        if bid == 0x10:
            pause, n = u16(d,o), u16(d,o+2); per_block_pauses.append(pause); o += 4+n
        elif bid == 0x11:
            pilot, sync1, sync2, zero, one, count = (u16(d,o+2*i) for i in range(6))
            used, pause, n = d[o+12], u16(d,o+13), u24(d,o+15)
            rom.append((pilot,sync1,sync2,zero,one,count,used,pause,n)); per_block_pauses.append(pause)
            o += 18+n
        elif bid == 0x12:
            o += 4
        elif bid == 0x13:
            n = d[o]; o += 1
            pulses.extend(u16(d,o+2*i) for i in range(n)); o += 2*n
        elif bid == 0x14:
            pause, n = u16(d,o+5), u24(d,o+7); per_block_pauses.append(pause); o += 10+n
        elif bid == 0x15:
            pause, n = u16(d,o+2), u24(d,o+5); per_block_pauses.append(pause); o += 8+n
        elif bid == 0x19:
            raise SystemExit(f"{path}: generalized-data block 0x19 remains in final TZX")
        elif bid == 0x20:
            explicit_pauses.append(u16(d,o)); o += 2
        elif bid in (0x21,0x30):
            n=d[o]; o += 1+n
        elif bid == 0x22:
            pass
        elif bid == 0x32:
            n=u16(d,o); o += 2+n
        elif bid == 0x5A:
            o += 9
        else:
            raise SystemExit(f"{path}: unhandled TZX block 0x{bid:02x}")
        if o > len(d):
            raise SystemExit(f"{path}: truncated TZX block 0x{bid:02x}")

    if [x[5] for x in rom[:2]] != ROM_PILOTS or len(rom) < 2:
        raise SystemExit(f"{path}: ROM pilot counts {[x[5] for x in rom]} != {ROM_PILOTS}")
    if explicit_pauses:
        raise SystemExit(f"{path}: explicit pause block(s) present: {explicit_pauses}")
    if any(per_block_pauses):
        raise SystemExit(f"{path}: nonzero per-block pause(s): {per_block_pauses}")
    if not pulses:
        raise SystemExit(f"{path}: no 0x13 fast pulse stream found")
    first = pulses[0]
    run = 1
    while run < len(pulses) and pulses[run] == first:
        run += 1
    if run != FAST_LEADER:
        raise SystemExit(f"{path}: fast leader has {run} pulses, expected {FAST_LEADER}")
    if first != FAST_LEADER_PULSE:
        raise SystemExit(f"{path}: fast leader pulse is {first} T-states, expected {FAST_LEADER_PULSE}")
    counts = collections.Counter(pulses[run:])
    for p in (ZERO, ONE):
        if counts[p] == 0:
            raise SystemExit(f"{path}: required turbo pulse {p} T-states not found")
    # ZQLoader adds a 64-T-state end-of-byte delay to the last pulse of each byte.
    for p in (ZERO + BYTE_DELAY, ONE + BYTE_DELAY):
        if counts[p] == 0:
            raise SystemExit(f"{path}: expected byte-boundary turbo pulse {p} T-states not found")
    if counts[1140] or counts[2280]:
        raise SystemExit(f"{path}: legacy ~1.5x pulses 1140/2280 still present")
    print(f"TZX OK: pilots {ROM_PILOTS[0]}/{ROM_PILOTS[1]}, fast leader {run}x{first}, turbo {ZERO}/{ONE}, no pauses")
    print("TZX blocks:", dict(sorted(collections.Counter(ids).items())))


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('tzx'); a=ap.parse_args(); validate(a.tzx)
if __name__=='__main__': main()
