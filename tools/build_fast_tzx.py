#!/usr/bin/env python3
"""Build the compact fast TZX with a fixed resident loader."""
from pathlib import Path
import argparse
import struct

PROG = 23755
LOADER_ADDR = 23784
ROM_PILOT = 2168
ROM_SYNC1 = 667
ROM_SYNC2 = 735
ZERO = 855
ONE = 1710
ROM_PILOTS = (2824, 2420)
FAST_PILOT = 1710
FAST_PULSES = 256

TOK_RANDOMIZE = 0xF9
TOK_USR = 0xC0
TOK_STOP = 0xE2
TOK_REM = 0xEA


def num(n):
    return str(n).encode('ascii') + bytes([0x0E, 0, 0, n & 255, n >> 8, 0])


def line(no, *parts):
    body = bytearray()
    for part in parts:
        if isinstance(part, int):
            body.append(part)
        elif isinstance(part, bytes):
            body += part
        else:
            body += part.encode('ascii')
    body.append(13)
    return bytes([no >> 8, no & 255, len(body) & 255, len(body) >> 8]) + body


def xor_record(flag, data):
    payload = bytes([flag]) + data
    check = 0
    for value in payload:
        check ^= value
    return payload + bytes([check])


def basic_header(length):
    name = b'CarromZX  '
    body = bytes([0]) + name + struct.pack('<HHH', length, 10, length)
    return xor_record(0, body)


def basic_program(loader):
    l10 = line(10, TOK_RANDOMIZE, TOK_USR, num(LOADER_ADDR))
    l20 = line(20, TOK_STOP)
    l200 = line(200, TOK_REM, loader)
    actual = PROG + len(l10) + len(l20) + 5
    if actual != LOADER_ADDR:
        raise SystemExit(f'loader address {actual} != {LOADER_ADDR}')
    program = l10 + l20 + l200
    if LOADER_ADDR + len(loader) >= 32768:
        raise SystemExit('loader overlaps the game load boundary')
    return program


def tzx11(data, pilot_count):
    head = struct.pack(
        '<HHHHHHB',
        ROM_PILOT, ROM_SYNC1, ROM_SYNC2, ZERO, ONE, pilot_count, 8
    )
    return bytes([0x11]) + head + struct.pack('<H', 0) + len(data).to_bytes(3, 'little') + data


def rolling_check(data):
    s1 = 0
    s2 = 0
    for value in data:
        s1 = (s1 + value) & 255
        s2 = (s2 + s1) & 255
    return bytes([s1, s2])


def fast_block(data):
    packed = data + rolling_check(data)

    body = bytearray()
    body += struct.pack('<H', 0)
    body += struct.pack('<I', 2)
    body += bytes([2, 2])
    body += struct.pack('<I', len(packed) * 8)
    body += bytes([1, 2])

    body += bytes([0]) + struct.pack('<HH', FAST_PILOT, FAST_PILOT)
    body += bytes([0]) + struct.pack('<HH', ROM_SYNC1, ROM_SYNC2)

    body += bytes([0]) + struct.pack('<H', FAST_PULSES // 2)
    body += bytes([1]) + struct.pack('<H', 1)

    body += bytes([0]) + struct.pack('<H', ZERO)
    body += bytes([0]) + struct.pack('<H', ONE)

    body += packed
    return bytes([0x19]) + struct.pack('<I', len(body)) + body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--loader', required=True)
    ap.add_argument('--screen', required=True)
    ap.add_argument('--game', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()

    loader = Path(a.loader).read_bytes()
    screen = Path(a.screen).read_bytes()
    game = Path(a.game).read_bytes()

    if len(screen) != 6912:
        raise SystemExit(f'loading screen is {len(screen)} bytes, expected 6912')
    if len(game) != 24565:
        raise SystemExit(f'game is {len(game)} bytes, expected 24565')

    program = basic_program(loader)
    blocks = [
        tzx11(basic_header(len(program)), ROM_PILOTS[0]),
        tzx11(xor_record(0xFF, program), ROM_PILOTS[1]),
        fast_block(screen),
        fast_block(game),
    ]
    image = b'ZXTape!\x1a' + bytes([1, 20]) + b''.join(blocks)
    Path(a.out).write_bytes(image)
    print(f'{a.out}: {len(image)} bytes, four blocks, loader {len(loader)} bytes')


if __name__ == '__main__':
    main()
