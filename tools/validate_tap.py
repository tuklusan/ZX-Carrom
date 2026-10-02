#!/usr/bin/env python3
"""Validate the accepted Carrom Arena standard TAP structure and payload."""
from pathlib import Path
import argparse, struct

LOAD_ADDRESS = 32768
ENTRY_POINT = 32768


def xor_all(data):
    x = 0
    for b in data:
        x ^= b
    return x


def parse(path):
    d = Path(path).read_bytes()
    o = 0
    blocks = []
    while o < len(d):
        if o + 2 > len(d):
            raise SystemExit(f"{path}: truncated TAP length at offset {o}")
        n = struct.unpack_from('<H', d, o)[0]
        o += 2
        if n < 2 or o + n > len(d):
            raise SystemExit(f"{path}: bad TAP block length {n} at offset {o-2}")
        b = d[o:o+n]
        if xor_all(b):
            raise SystemExit(f"{path}: checksum failure in block {len(blocks)}")
        blocks.append(b)
        o += n
    return blocks


def header_fields(b):
    if len(b) != 19 or b[0] != 0:
        raise SystemExit("expected a 19-byte TAP header block")
    typ = b[1]
    name = b[2:12].decode('ascii').rstrip()
    length, p1, p2 = struct.unpack_from('<HHH', b, 12)
    return typ, name, length, p1, p2


def validate(tap_path, bin_path):
    blocks = parse(tap_path)
    if len(blocks) != 4:
        raise SystemExit(f"{tap_path}: expected 4 TAP blocks, found {len(blocks)}")
    bh, bd, ch, cd = blocks
    bt, bn, blen, brun, bvars = header_fields(bh)
    if bt != 0 or brun != 10 or blen != len(bd) - 2 or bvars != blen:
        raise SystemExit(f"{tap_path}: invalid BASIC header: {(bt,bn,blen,brun,bvars)}")
    if bd[0] != 0xFF:
        raise SystemExit(f"{tap_path}: BASIC data block has flag 0x{bd[0]:02x}, expected 0xff")
    basic = bd[1:-1]
    if b'32767' not in basic or b'32768' not in basic:
        raise SystemExit(f"{tap_path}: BASIC loader does not contain CLEAR 32767 / USR 32768 literals")

    ct, cn, clen, load, p2 = header_fields(ch)
    code = cd[1:-1]
    expected = Path(bin_path).read_bytes()
    if ct != 3 or load != LOAD_ADDRESS or p2 != ENTRY_POINT:
        raise SystemExit(f"{tap_path}: invalid CODE header: {(ct,cn,clen,load,p2)}")
    if cd[0] != 0xFF:
        raise SystemExit(f"{tap_path}: CODE data block has flag 0x{cd[0]:02x}, expected 0xff")
    if clen != len(code) or code != expected:
        raise SystemExit(f"{tap_path}: CODE payload differs from {bin_path} ({len(code)} vs {len(expected)} bytes)")
    if len(code) >= 0x6000:
        raise SystemExit(f"{tap_path}: machine code is too large: {len(code)} bytes")
    print(f"TAP OK: 4 blocks, BASIC {len(basic)} bytes, CODE {len(code)} bytes, load/entry {LOAD_ADDRESS}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tap')
    ap.add_argument('binary')
    a = ap.parse_args()
    validate(a.tap, a.binary)


if __name__ == '__main__':
    main()
