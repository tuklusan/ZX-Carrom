#!/usr/bin/env python3
"""Independently parse and validate the accepted compact fast TZX."""
from pathlib import Path
import argparse, collections, struct

ROM_PILOTS = [2824, 2420]
FAST_LEADER = 256
FAST_LEADER_PULSE = 1710
ZERO = 855
ONE = 1710
BYTE_DELAY = 64
MAX_SIZE = 131072

def u16(d, o): return struct.unpack_from('<H', d, o)[0]
def u24(d, o): return int.from_bytes(d[o:o+3], 'little')
def u32(d, o): return struct.unpack_from('<I', d, o)[0]

def parse_gdb(body):
    if len(body) < 18:
        raise SystemExit('short generalized-data block')
    pause = u16(body, 4)
    totp, npp, asp = u32(body, 6), body[10], body[11] or 256
    totd, npd, asd = u32(body, 12), body[16], body[17] or 256
    p = 18
    psyms = []
    for _ in range(asp if totp else 0):
        if p + 1 + 2*npp > len(body): raise SystemExit('truncated pilot symbols')
        vals=[u16(body,p+1+2*k) for k in range(npp)]
        psyms.append([x for x in vals if x])
        p += 1 + 2*npp
    prle=[]
    for _ in range(totp):
        if p+3 > len(body): raise SystemExit('truncated pilot sequence')
        prle.append((body[p],u16(body,p+1))); p += 3
    dsyms=[]
    for _ in range(asd if totd else 0):
        if p + 1 + 2*npd > len(body): raise SystemExit('truncated data symbols')
        vals=[u16(body,p+1+2*k) for k in range(npd)]
        dsyms.append([x for x in vals if x])
        p += 1 + 2*npd
    return pause, totd, psyms, prle, dsyms

def validate(path):
    d = Path(path).read_bytes()
    if len(d) > MAX_SIZE:
        raise SystemExit(f"{path}: expanded TZX is {len(d)} bytes, limit is {MAX_SIZE}")
    if d[:8] != b'ZXTape!\x1a' or len(d) < 10:
        raise SystemExit(f"{path}: bad TZX header")

    o=10
    ids=[]; rom=[]; explicit=[]; pauses=[]; timing=collections.Counter()
    leaders=[]
    while o < len(d):
        bid=d[o]; o+=1; ids.append(bid)
        if bid == 0x10:
            pause,n=u16(d,o),u16(d,o+2); pauses.append(pause); o += 4+n
        elif bid == 0x11:
            pilot,sync1,sync2,zero,one,count=(u16(d,o+2*i) for i in range(6))
            used,pause,n=d[o+12],u16(d,o+13),u24(d,o+15)
            rom.append((pilot,sync1,sync2,zero,one,count,used,pause,n)); pauses.append(pause); o += 18+n
        elif bid == 0x12:
            pulse,count=u16(d,o),u16(d,o+2)
            if pulse == FAST_LEADER_PULSE: leaders.append(count)
            o += 4
        elif bid == 0x13:
            raise SystemExit(f"{path}: expanded pulse-sequence block 0x13 remains")
        elif bid == 0x14:
            pause,n=u16(d,o+5),u24(d,o+7); pauses.append(pause); o += 10+n
        elif bid == 0x15:
            pause,n=u16(d,o+2),u24(d,o+5); pauses.append(pause); o += 8+n
        elif bid == 0x19:
            n=u32(d,o); body=d[o:o+4+n]
            pause,totd,psyms,prle,dsyms=parse_gdb(body); pauses.append(pause)
            if not totd:
                raise SystemExit(f"{path}: timing-only generalized block remains")
            if len(prle) >= 2:
                sym,rep=prle[0]
                if sym < len(psyms) and psyms[sym] and all(x == FAST_LEADER_PULSE for x in psyms[sym]):
                    leaders.append(rep*len(psyms[sym]))
            for sym in dsyms:
                timing.update(sym)
            o += 4+n
        elif bid == 0x20:
            explicit.append(u16(d,o)); o += 2
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
        if o > len(d): raise SystemExit(f"{path}: truncated TZX block 0x{bid:02x}")

    if len(rom) < 2 or [x[5] for x in rom[:2]] != ROM_PILOTS:
        raise SystemExit(f"{path}: ROM pilot counts {[x[5] for x in rom]} != {ROM_PILOTS}")
    if explicit: raise SystemExit(f"{path}: explicit pause block(s) present: {explicit}")
    if any(pauses): raise SystemExit(f"{path}: nonzero per-block pause(s): {pauses}")
    if leaders != [FAST_LEADER, FAST_LEADER]:
        raise SystemExit(f"{path}: fast leaders are {leaders}, expected two blocks of {FAST_LEADER}")
    for p in (ZERO,ONE,ZERO+BYTE_DELAY,ONE+BYTE_DELAY):
        if not timing[p]: raise SystemExit(f"{path}: required turbo timing {p} T-states not found")
    if timing[1140] or timing[2280]:
        raise SystemExit(f"{path}: legacy slower pulses remain")
    if 0x19 not in ids:
        raise SystemExit(f"{path}: compact generalized-data blocks missing")
    print(f"TZX OK: {len(d)} bytes, pilots {ROM_PILOTS[0]}/{ROM_PILOTS[1]}, fast leaders {leaders}x{FAST_LEADER_PULSE}, turbo {ZERO}/{ONE}, no pauses")
    print("TZX blocks:", dict(sorted(collections.Counter(ids).items())))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('tzx'); a=ap.parse_args(); validate(a.tzx)
if __name__=='__main__': main()
