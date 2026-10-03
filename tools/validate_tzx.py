#!/usr/bin/env python3
"""Independently parse and validate the accepted pulse-stream fast TZX."""
from pathlib import Path
import argparse, collections, struct

ROM_PILOTS = [2824, 2420]
FAST_LEADER = 256
FAST_LEADER_PULSE = 1710
ZERO = 855
ONE = 1710
BYTE_DELAY = 64
HEADER_LEN = 17
SCREEN_LEN = 6912
MAX_SIZE = 1024 * 1024


def u16(d, o): return struct.unpack_from('<H', d, o)[0]
def u24(d, o): return int.from_bytes(d[o:o+3], 'little')
def u32(d, o): return struct.unpack_from('<I', d, o)[0]


def decode_bytes(pulses, pos, count, label):
    out = bytearray()
    for byte_index in range(count):
        value = 0
        for bit_index in range(8):
            if pos >= len(pulses):
                raise SystemExit(f'truncated {label} at byte {byte_index}')
            pulse = pulses[pos]
            pos += 1
            if bit_index == 7:
                pulse -= BYTE_DELAY
            if pulse == ZERO:
                bit = 0
            elif pulse == ONE:
                bit = 1
            else:
                raise SystemExit(f'{label}: bad pulse {pulse} at byte {byte_index}, bit {bit_index}')
            value = (value << 1) | bit
        out.append(value)
    return bytes(out), pos


def turbo_checksum(payload):
    value = 1
    for byte in payload:
        value = (byte + value) & 0xFF
        value = ((value << 1) | (value >> 7)) & 0xFF
    return value


def header_fields(header):
    return {
        'length': u16(header, 0),
        'load': u16(header, 2),
        'dest': u16(header, 4),
        'compression': header[6],
        'checksum': header[7],
        'usr': u16(header, 8),
        'clear': u16(header, 10),
    }


def expect_leader(pulses, pos, number):
    end = pos + FAST_LEADER
    if end > len(pulses) or any(p != FAST_LEADER_PULSE for p in pulses[pos:end]):
        raise SystemExit(f'fast leader {number} is not {FAST_LEADER} x {FAST_LEADER_PULSE}')
    pos = end
    if pulses[pos:pos+2] != [250, 499]:
        raise SystemExit(f'fast leader {number}: sync pulses are {pulses[pos:pos+2]}, expected [250, 499]')
    return pos + 2


def validate_fast_stream(pulses, bin_path=None):
    pos = 0
    payloads = []
    headers = []
    for number in (1, 2):
        pos = expect_leader(pulses, pos, number)
        raw_header, pos = decode_bytes(pulses, pos, HEADER_LEN, f'header {number}')
        fields = header_fields(raw_header)
        headers.append(fields)
        if pos >= len(pulses) or pulses[pos] != 501:
            got = pulses[pos] if pos < len(pulses) else None
            raise SystemExit(f'header {number}: minisync is {got}, expected 501')
        pos += 1
        payload, pos = decode_bytes(pulses, pos, fields['length'], f'payload {number}')
        if turbo_checksum(payload) != fields['checksum']:
            raise SystemExit(f'payload {number}: turbo checksum mismatch')
        payloads.append(payload)

    if pos != len(pulses):
        raise SystemExit(f'extra turbo pulses remain after game payload: {len(pulses) - pos}')

    screen, game = headers
    if (screen['length'], screen['load'], screen['dest'], screen['compression'], screen['usr']) != (SCREEN_LEN, 16384, 0, 0, 0x0100):
        raise SystemExit(f'loading-screen turbo header is wrong: {screen}')
    if (game['load'], game['dest'], game['compression'], game['usr'], game['clear']) != (32768, 0, 0, 32768, 32767):
        raise SystemExit(f'game turbo header does not jump cleanly to 32768: {game}')

    if bin_path:
        expected = Path(bin_path).read_bytes()
        if game['length'] != len(expected):
            raise SystemExit(f'game turbo length {game["length"]} != binary length {len(expected)}')
        if payloads[1] != expected:
            raise SystemExit('game turbo payload differs from freshly assembled binary')
    return headers


def validate(path, bin_path=None):
    d = Path(path).read_bytes()
    if len(d) > MAX_SIZE:
        raise SystemExit(f"{path}: TZX is {len(d)} bytes, limit is {MAX_SIZE}")
    if d[:8] != b'ZXTape!\x1a' or len(d) < 10:
        raise SystemExit(f"{path}: bad TZX header")

    o = 10
    ids = []
    rom = []
    explicit = []
    pauses = []
    pulses = []
    while o < len(d):
        bid = d[o]
        o += 1
        ids.append(bid)
        if bid == 0x10:
            pause, n = u16(d, o), u16(d, o + 2)
            pauses.append(pause)
            o += 4 + n
        elif bid == 0x11:
            pilot, sync1, sync2, zero, one, count = (u16(d, o + 2*i) for i in range(6))
            used, pause, n = d[o+12], u16(d, o+13), u24(d, o+15)
            rom.append((pilot, sync1, sync2, zero, one, count, used, pause, n))
            pauses.append(pause)
            o += 18 + n
        elif bid == 0x12:
            pulse, count = u16(d, o), u16(d, o + 2)
            pulses.extend([pulse] * count)
            o += 4
        elif bid == 0x13:
            count = d[o]
            pulses.extend(u16(d, o + 1 + 2*k) for k in range(count))
            o += 1 + 2 * count
        elif bid == 0x14:
            pause, n = u16(d, o+5), u24(d, o+7)
            pauses.append(pause)
            o += 10 + n
        elif bid == 0x15:
            pause, n = u16(d, o+2), u24(d, o+5)
            pauses.append(pause)
            o += 8 + n
        elif bid == 0x19:
            raise SystemExit(f"{path}: generalized-data block remains in release TZX")
        elif bid == 0x20:
            explicit.append(u16(d, o))
            o += 2
        elif bid in (0x21, 0x30):
            n = d[o]
            o += 1 + n
        elif bid == 0x22:
            pass
        elif bid == 0x32:
            n = u16(d, o)
            o += 2 + n
        elif bid == 0x5A:
            o += 9
        else:
            raise SystemExit(f"{path}: unhandled TZX block 0x{bid:02x}")
        if o > len(d):
            raise SystemExit(f"{path}: truncated TZX block 0x{bid:02x}")

    if len(rom) != 2 or [x[5] for x in rom] != ROM_PILOTS:
        raise SystemExit(f"{path}: ROM pilot counts {[x[5] for x in rom]} != {ROM_PILOTS}")
    if explicit:
        raise SystemExit(f"{path}: explicit pause block(s) present: {explicit}")
    if any(pauses):
        raise SystemExit(f"{path}: nonzero per-block pause(s): {pauses}")
    if 0x13 not in ids:
        raise SystemExit(f"{path}: pulse-sequence turbo stream missing")

    timing = collections.Counter(pulses)
    for pulse in (ZERO, ONE, ZERO + BYTE_DELAY, ONE + BYTE_DELAY):
        if not timing[pulse]:
            raise SystemExit(f"{path}: required turbo timing {pulse} T-states not found")
    if timing[1140] or timing[2280]:
        raise SystemExit(f"{path}: legacy slower pulses remain")

    headers = validate_fast_stream(pulses, bin_path)
    print(f"TZX OK: {len(d)} bytes, pilots {ROM_PILOTS[0]}/{ROM_PILOTS[1]}, "
          f"fast leaders 2x{FAST_LEADER}x{FAST_LEADER_PULSE}, turbo {ZERO}/{ONE}, "
          f"no pauses, final jump {headers[1]['usr']}")
    print("TZX blocks:", dict(sorted(collections.Counter(ids).items())))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tzx')
    ap.add_argument('binary', nargs='?')
    a = ap.parse_args()
    validate(a.tzx, a.binary)


if __name__ == '__main__':
    main()
