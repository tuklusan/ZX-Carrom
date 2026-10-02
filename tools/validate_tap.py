#!/usr/bin/env python3
"""Validate the accepted standard tape structure and payload."""
from pathlib import Path
import argparse, struct

LOAD_ADDRESS=32768
ENTRY_POINT=32768
SCREEN_ADDRESS=16384
SCREEN_SIZE=6912

def xor_all(data):
    x=0
    for b in data: x ^= b
    return x

def parse(path):
    d=Path(path).read_bytes(); o=0; blocks=[]
    while o < len(d):
        if o+2 > len(d): raise SystemExit(f"{path}: truncated TAP length at offset {o}")
        n=struct.unpack_from('<H',d,o)[0]; o += 2
        if n < 2 or o+n > len(d): raise SystemExit(f"{path}: bad TAP block length {n} at offset {o-2}")
        b=d[o:o+n]
        if xor_all(b): raise SystemExit(f"{path}: checksum failure in block {len(blocks)}")
        blocks.append(b); o += n
    return blocks

def header_fields(b):
    if len(b)!=19 or b[0]!=0: raise SystemExit("expected a 19-byte TAP header block")
    return b[1],b[2:12].decode('ascii').rstrip(),*struct.unpack_from('<HHH',b,12)

def validate(tap_path,bin_path):
    blocks=parse(tap_path)
    if len(blocks)!=6: raise SystemExit(f"{tap_path}: expected 6 TAP blocks, found {len(blocks)}")
    bh,bd,sh,sd,ch,cd=blocks
    bt,bn,blen,brun,bvars=header_fields(bh)
    if bt!=0 or brun!=10 or blen!=len(bd)-2 or bvars!=blen:
        raise SystemExit(f"{tap_path}: invalid BASIC header: {(bt,bn,blen,brun,bvars)}")
    if bd[0]!=0xFF: raise SystemExit(f"{tap_path}: BASIC data flag is 0x{bd[0]:02x}")
    basic=bd[1:-1]
    if b'32767' not in basic or b'32768' not in basic or bytes([0xAA]) not in basic:
        raise SystemExit(f"{tap_path}: BASIC loader sequence is incomplete")

    st,sn,slen,sload,sp2=header_fields(sh)
    screen=sd[1:-1]
    if st!=3 or sload!=SCREEN_ADDRESS or slen!=SCREEN_SIZE or len(screen)!=SCREEN_SIZE:
        raise SystemExit(f"{tap_path}: invalid SCREEN block: {(st,sn,slen,sload,sp2)}")
    if sd[0]!=0xFF or not any(screen[:6144]) or not any(screen[6144:]):
        raise SystemExit(f"{tap_path}: SCREEN payload is invalid")

    ct,cn,clen,load,p2=header_fields(ch)
    code=cd[1:-1]; expected=Path(bin_path).read_bytes()
    if ct!=3 or load!=LOAD_ADDRESS or p2!=ENTRY_POINT:
        raise SystemExit(f"{tap_path}: invalid CODE header: {(ct,cn,clen,load,p2)}")
    if cd[0]!=0xFF: raise SystemExit(f"{tap_path}: CODE data flag is 0x{cd[0]:02x}")
    if clen!=len(code) or code!=expected:
        raise SystemExit(f"{tap_path}: CODE payload differs from {bin_path}")
    if len(code)>=0x6000: raise SystemExit(f"{tap_path}: machine code is too large: {len(code)} bytes")
    print(f"TAP OK: 6 blocks, BASIC {len(basic)} bytes, SCREEN {len(screen)} bytes, CODE {len(code)} bytes, load/entry {LOAD_ADDRESS}")

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('tap'); ap.add_argument('binary'); a=ap.parse_args()
    validate(a.tap,a.binary)

if __name__=='__main__': main()
