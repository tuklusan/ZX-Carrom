#!/usr/bin/env python3
"""Independently parse and validate the compact fast TZX."""
from pathlib import Path
import argparse, collections, struct

ROM_PILOTS = [2824, 2420]
FAST_LEADER = 256
FAST_PULSE = 1710
ZERO = 855
ONE = 1710
HEADER_LEN = 17
SCREEN_LEN = 6912
MAX_SIZE = 65536
EXPECTED_IDS = [0x30, 0x11, 0x11, 0x11, 0x12, 0x14, 0x11, 0x12, 0x14]


def u16(d, o): return struct.unpack_from('<H', d, o)[0]
def u24(d, o): return int.from_bytes(d[o:o+3], 'little')


def checksum(payload):
    value = 1
    for byte in payload:
        value = (byte + value) & 0xFF
        value = ((value << 1) | (value >> 7)) & 0xFF
    return value


def fields(header):
    if len(header) != HEADER_LEN:
        raise SystemExit(f'fast header length is {len(header)}, expected {HEADER_LEN}')
    return {
        'length': u16(header, 0),
        'load': u16(header, 2),
        'dest': u16(header, 4),
        'compression': header[6],
        'sum': header[7],
        'usr': u16(header, 8),
        'clear': u16(header, 10),
    }


def parse(path):
    d = Path(path).read_bytes()
    if len(d) > MAX_SIZE:
        raise SystemExit(f'{path}: TZX is {len(d)} bytes, limit is {MAX_SIZE}')
    if len(d) < 10 or d[:8] != b'ZXTape!\x1a':
        raise SystemExit(f'{path}: bad TZX header')

    o = 10
    blocks = []
    while o < len(d):
        bid = d[o]
        o += 1
        if bid == 0x30:
            n = d[o]
            blocks.append((bid, {'text': bytes(d[o+1:o+1+n])}))
            o += 1 + n
        elif bid == 0x11:
            pilot, sync1, sync2, zero, one, count = (u16(d, o + 2*i) for i in range(6))
            used, pause, n = d[o+12], u16(d, o+13), u24(d, o+15)
            data = bytes(d[o+18:o+18+n])
            blocks.append((bid, {
                'pilot': pilot, 'sync1': sync1, 'sync2': sync2,
                'zero': zero, 'one': one, 'count': count,
                'used': used, 'pause': pause, 'data': data,
            }))
            o += 18 + n
        elif bid == 0x12:
            blocks.append((bid, {'pulse': u16(d, o), 'count': u16(d, o+2)}))
            o += 4
        elif bid == 0x14:
            zero, one = u16(d, o), u16(d, o+2)
            used, pause, n = d[o+4], u16(d, o+5), u24(d, o+7)
            data = bytes(d[o+10:o+10+n])
            blocks.append((bid, {
                'zero': zero, 'one': one, 'used': used,
                'pause': pause, 'data': data,
            }))
            o += 10 + n
        elif bid == 0x20:
            raise SystemExit(f'{path}: explicit pause block present')
        elif bid == 0x19:
            raise SystemExit(f'{path}: generalized-data block remains')
        elif bid == 0x13:
            raise SystemExit(f'{path}: expanded pulse-sequence block remains')
        else:
            raise SystemExit(f'{path}: unexpected TZX block 0x{bid:02X}')
        if o > len(d):
            raise SystemExit(f'{path}: truncated TZX block 0x{bid:02X}')

    if o != len(d):
        raise SystemExit(f'{path}: trailing bytes')
    return d, blocks


def validate(path, bin_path=None):
    d, blocks = parse(path)
    ids = [bid for bid, _ in blocks]
    if ids != EXPECTED_IDS:
        raise SystemExit(f'{path}: TZX block sequence {ids} != {EXPECTED_IDS}')

    rom = [blocks[1][1], blocks[2][1]]
    if [x['count'] for x in rom] != ROM_PILOTS:
        raise SystemExit(f'{path}: ROM pilot counts {[x["count"] for x in rom]} != {ROM_PILOTS}')
    if any(x['pause'] for x in rom):
        raise SystemExit(f'{path}: ROM block pause is not zero')

    fast_headers = [blocks[3][1], blocks[6][1]]
    tones = [blocks[4][1], blocks[7][1]]
    payloads = [blocks[5][1], blocks[8][1]]

    for number, block in enumerate(fast_headers, 1):
        got = (block['pilot'], block['sync1'], block['sync2'], block['zero'],
               block['one'], block['count'], block['used'], block['pause'])
        want = (FAST_PULSE, 250, 499, ZERO, ONE, FAST_LEADER, 8, 0)
        if got != want:
            raise SystemExit(f'fast header block {number} timing {got} != {want}')
        if len(block['data']) != HEADER_LEN:
            raise SystemExit(f'fast header block {number} has {len(block["data"])} bytes')

    for number, tone in enumerate(tones, 1):
        if (tone['pulse'], tone['count']) != (501, 1):
            raise SystemExit(f'minisync {number} is {tone}')

    for number, block in enumerate(payloads, 1):
        got = (block['zero'], block['one'], block['used'], block['pause'])
        if got != (ZERO, ONE, 8, 0):
            raise SystemExit(f'fast payload block {number} timing {got}')
        h = fields(fast_headers[number-1]['data'])
        if len(block['data']) != h['length']:
            raise SystemExit(f'fast payload block {number} length mismatch')
        if checksum(block['data']) != h['sum']:
            raise SystemExit(f'fast payload block {number} checksum mismatch')

    screen = fields(fast_headers[0]['data'])
    game = fields(fast_headers[1]['data'])
    if (screen['length'], screen['load'], screen['dest'], screen['compression'], screen['usr']) != (SCREEN_LEN, 16384, 0, 0, 0x0100):
        raise SystemExit(f'loading-screen fast header is wrong: {screen}')
    if (game['load'], game['dest'], game['compression'], game['usr'], game['clear']) != (32768, 0, 0, 32768, 32767):
        raise SystemExit(f'game fast header does not jump to 32768: {game}')

    if bin_path:
        expected = Path(bin_path).read_bytes()
        if game['length'] != len(expected):
            raise SystemExit(f'game fast length {game["length"]} != binary length {len(expected)}')
        if payloads[1]['data'] != expected:
            raise SystemExit('game fast payload differs from freshly assembled binary')

    counts = dict(sorted(collections.Counter(ids).items()))
    print(f'TZX OK: {len(d)} bytes, pilots {ROM_PILOTS[0]}/{ROM_PILOTS[1]}, '
          f'fast leaders 2x{FAST_LEADER} at {FAST_PULSE}, turbo {ZERO}/{ONE}, '
          f'no pauses, jump {game["usr"]}')
    print('TZX blocks:', counts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tzx')
    ap.add_argument('binary', nargs='?')
    a = ap.parse_args()
    validate(a.tzx, a.binary)


if __name__ == '__main__':
    main()
