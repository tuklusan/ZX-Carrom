#!/usr/bin/env python3
"""Validate the fixed-sequence compact fast TZX."""
from pathlib import Path
import argparse
import struct

PROG = 23755
LOADER_ADDR = 23797
ROM_PILOT = 2168
ROM_SYNC1 = 667
ROM_SYNC2 = 735
ZERO = 855
ONE = 1710
ROM_PILOTS = (512, 512)
FAST_PILOT = 1710
FAST_PULSES = 256
MAX_SIZE = 40000


def u16(data, pos):
    return struct.unpack_from('<H', data, pos)[0]


def u24(data, pos):
    return int.from_bytes(data[pos:pos + 3], 'little')


def u32(data, pos):
    return struct.unpack_from('<I', data, pos)[0]


def xor_ok(data):
    value = 0
    for byte in data:
        value ^= byte
    return value == 0


def rolling_check(data):
    s1 = 0
    s2 = 0
    for value in data:
        s1 = (s1 + value) & 255
        s2 = (s2 + s1) & 255
    return bytes([s1, s2])


def parse_11(data, pos):
    pilot, sync1, sync2, zero, one, count = (
        u16(data, pos + 2 * i) for i in range(6)
    )
    used = data[pos + 12]
    pause = u16(data, pos + 13)
    size = u24(data, pos + 15)
    start = pos + 18
    end = start + size
    if end > len(data):
        raise SystemExit('truncated 0x11 block')
    return {
        'pilot': pilot, 'sync1': sync1, 'sync2': sync2,
        'zero': zero, 'one': one, 'count': count,
        'used': used, 'pause': pause, 'data': data[start:end],
    }, end


def parse_19(data, pos):
    size = u32(data, pos)
    end = pos + 4 + size
    if end > len(data):
        raise SystemExit('truncated 0x19 block')
    body = data[pos + 4:end]
    if len(body) < 14:
        raise SystemExit('short 0x19 body')

    pause = u16(body, 0)
    totp = u32(body, 2)
    npp = body[6]
    asp = body[7] or 256
    totd = u32(body, 8)
    npd = body[12]
    asd = body[13] or 256
    p = 14

    psyms = []
    for _ in range(asp if totp else 0):
        flag = body[p]
        vals = [u16(body, p + 1 + 2 * k) for k in range(npp)]
        psyms.append((flag, vals))
        p += 1 + 2 * npp

    prle = []
    for _ in range(totp):
        prle.append((body[p], u16(body, p + 1)))
        p += 3

    dsyms = []
    for _ in range(asd if totd else 0):
        flag = body[p]
        vals = [u16(body, p + 1 + 2 * k) for k in range(npd)]
        dsyms.append((flag, vals))
        p += 1 + 2 * npd

    bits = max(1, (asd - 1).bit_length())
    packed_size = (totd * bits + 7) // 8
    packed = bytes(body[p:p + packed_size])
    p += packed_size
    if p != len(body):
        raise SystemExit('0x19 body has trailing bytes')

    return {
        'pause': pause, 'totp': totp, 'npp': npp, 'asp': asp,
        'totd': totd, 'npd': npd, 'asd': asd,
        'psyms': psyms, 'prle': prle, 'dsyms': dsyms,
        'packed': packed,
    }, end


def check_rom(block, pilot_count):
    got = (
        block['pilot'], block['sync1'], block['sync2'],
        block['zero'], block['one'], block['count'],
        block['used'], block['pause'],
    )
    want = (
        ROM_PILOT, ROM_SYNC1, ROM_SYNC2,
        ZERO, ONE, pilot_count, 8, 0,
    )
    if got != want:
        raise SystemExit(f'ROM block timing {got} != {want}')


def check_fast(block, expected, label):
    if block['pause'] != 0:
        raise SystemExit(f'{label}: pause is not zero')
    if (block['totp'], block['npp'], block['asp']) != (2, 2, 2):
        raise SystemExit(f'{label}: pilot layout is wrong')
    if (block['npd'], block['asd']) != (1, 2):
        raise SystemExit(f'{label}: data layout is wrong')
    if block['psyms'] != [
        (0, [FAST_PILOT, FAST_PILOT]),
        (0, [ROM_SYNC1, ROM_SYNC2]),
    ]:
        raise SystemExit(f'{label}: pilot/sync symbols are wrong')
    if block['prle'] != [(0, FAST_PULSES // 2), (1, 1)]:
        raise SystemExit(f'{label}: fast leader is wrong')
    if block['dsyms'] != [(0, [ZERO]), (0, [ONE])]:
        raise SystemExit(f'{label}: data timings are wrong')

    packed = expected + rolling_check(expected)
    if block['totd'] != len(packed) * 8:
        raise SystemExit(f'{label}: symbol count is wrong')
    if block['packed'] != packed:
        raise SystemExit(f'{label}: payload/checksum mismatch')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tzx')
    ap.add_argument('--loader', required=True)
    ap.add_argument('--screen', required=True)
    ap.add_argument('--game', required=True)
    a = ap.parse_args()

    data = Path(a.tzx).read_bytes()
    loader = Path(a.loader).read_bytes()
    screen = Path(a.screen).read_bytes()
    game = Path(a.game).read_bytes()

    if len(data) > MAX_SIZE:
        raise SystemExit(f'TZX is {len(data)} bytes, limit is {MAX_SIZE}')
    if data[:8] != b'ZXTape!\x1a' or data[8:10] != bytes([1, 20]):
        raise SystemExit('bad TZX header/version')

    pos = 10
    ids = []
    parsed = []
    while pos < len(data):
        block_id = data[pos]
        ids.append(block_id)
        pos += 1
        if block_id == 0x11:
            block, pos = parse_11(data, pos)
        elif block_id == 0x19:
            block, pos = parse_19(data, pos)
        else:
            raise SystemExit(f'unexpected TZX block 0x{block_id:02X}')
        parsed.append(block)

    if pos != len(data):
        raise SystemExit('trailing bytes after final block')
    if ids != [0x11, 0x11, 0x19, 0x19]:
        raise SystemExit(f'block sequence is {ids}')

    check_rom(parsed[0], ROM_PILOTS[0])
    check_rom(parsed[1], ROM_PILOTS[1])

    hdr = parsed[0]['data']
    basic = parsed[1]['data']
    if len(hdr) != 19 or hdr[0] != 0 or not xor_ok(hdr):
        raise SystemExit('bad BASIC header record')
    if hdr[1] != 0 or hdr[2:12] != b'CarromZX  ':
        raise SystemExit('bad BASIC header fields')
    basic_len = u16(hdr, 12)
    autorun = u16(hdr, 14)
    prog_len = u16(hdr, 16)
    if autorun != 10 or basic_len != prog_len:
        raise SystemExit('bad BASIC autostart/length')
    if len(basic) != basic_len + 2 or basic[0] != 0xFF or not xor_ok(basic):
        raise SystemExit('bad BASIC data record')

    program = basic[1:-1]
    loader_off = LOADER_ADDR - PROG
    if program[loader_off:loader_off + len(loader)] != loader:
        raise SystemExit('resident loader differs from assembled loader')
    if loader_off + len(loader) >= len(program):
        raise SystemExit('resident loader placement is invalid')

    check_fast(parsed[2], screen, 'screen block')
    check_fast(parsed[3], game, 'game block')

    print(
        f'TZX OK: {len(data)} bytes, blocks 11/11/19/19, '
        f'ROM pilots {ROM_PILOTS[0]}/{ROM_PILOTS[1]}, '
        f'fast leaders {FAST_PULSES}/{FAST_PULSES}, '
        f'data {ZERO}/{ONE}, no pauses'
    )


if __name__ == '__main__':
    main()
