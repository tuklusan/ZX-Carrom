#!/usr/bin/env python3
"""Finalize the turbo TZX using compact standard block types.

Production output uses 0x11 for each fast header, 0x12 for the one-pulse
minisync, and 0x14 for each fast payload.  The host tool may emit 0x19 blocks;
this file extracts their bytes and rewrites them without expanding every edge.
"""
import sys, struct

ROM_PILOTS = [2824, 2420]
FAST_LEADER = 256
FAST_PULSE = 1710
ZERO = 855
ONE = 1710
HEADER_LEN = 17


def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u24(b, o): return int.from_bytes(b[o:o+3], 'little')
def u32(b, o): return struct.unpack_from('<I', b, o)[0]


def block_len(d, o, bid):
    if bid == 0x10: return 4 + u16(d, o + 2)
    if bid == 0x11: return 18 + u24(d, o + 15)
    if bid == 0x12: return 4
    if bid == 0x13: return 1 + 2 * d[o]
    if bid == 0x14: return 10 + u24(d, o + 7)
    if bid == 0x15: return 8 + u24(d, o + 5)
    if bid == 0x19: return 4 + u32(d, o)
    if bid == 0x20: return 2
    if bid in (0x21, 0x30): return 1 + d[o]
    if bid == 0x22: return 0
    if bid == 0x32: return 2 + u16(d, o)
    if bid == 0x5A: return 9
    raise ValueError(f"TZX block 0x{bid:02X} not handled")


def shorten_legacy_pulses(pulses, limit=FAST_LEADER):
    """Keep the old multi-0x13 leader fix for comparison inputs."""
    if not pulses:
        return pulses
    first = pulses[0]
    run = 1
    while run < len(pulses) and pulses[run] == first:
        run += 1
    if run >= limit:
        return [FAST_PULSE] * limit + pulses[run:]
    return pulses


def emit_pulses(out, pulses):
    for i in range(0, len(pulses), 255):
        chunk = pulses[i:i + 255]
        out += bytes([0x13, len(chunk)])
        out += b''.join(struct.pack('<H', x) for x in chunk)


def parse_gdb(body):
    if len(body) < 18:
        raise ValueError('short generalized-data block')
    pause = u16(body, 4)
    totp, npp, asp = u32(body, 6), body[10], body[11] or 256
    totd, npd, asd = u32(body, 12), body[16], body[17] or 256
    p = 18

    psyms = []
    for _ in range(asp if totp else 0):
        if p + 1 + 2 * npp > len(body):
            raise ValueError('truncated generalized pilot table')
        vals = [u16(body, p + 1 + 2*k) for k in range(npp)]
        psyms.append([x for x in vals if x])
        p += 1 + 2 * npp

    prle = []
    for _ in range(totp):
        if p + 3 > len(body):
            raise ValueError('truncated generalized pilot stream')
        prle.append((body[p], u16(body, p + 1)))
        p += 3

    dsyms = []
    for _ in range(asd if totd else 0):
        if p + 1 + 2 * npd > len(body):
            raise ValueError('truncated generalized data table')
        vals = [u16(body, p + 1 + 2*k) for k in range(npd)]
        dsyms.append([x for x in vals if x])
        p += 1 + 2 * npd

    bits = max(1, (asd - 1).bit_length())
    packed = (totd * bits + 7) // 8
    if p + packed > len(body):
        raise ValueError('truncated generalized packed data')
    raw = bytes(body[p:p + packed])
    return {
        'pause': pause, 'totp': totp, 'npp': npp, 'asp': asp,
        'totd': totd, 'npd': npd, 'asd': asd,
        'psyms': psyms, 'prle': prle, 'dsyms': dsyms, 'raw': raw,
    }


def emit_fast_header(out, g, number):
    if g['pause']:
        raise ValueError(f'fast header {number} has a pause')
    if len(g['raw']) != HEADER_LEN:
        raise ValueError(f'fast header {number} is {len(g["raw"])} bytes')
    if g['totp'] < 2 or len(g['psyms']) < 2 or g['psyms'][1] != [250, 499]:
        raise ValueError(f'fast header {number} sync is not 250/499')
    if len(g['dsyms']) < 2 or g['dsyms'][0][0] != ZERO or g['dsyms'][1][0] != ONE:
        raise ValueError(f'fast header {number} data timing is not {ZERO}/{ONE}')

    data = g['raw']
    out.append(0x11)
    out += struct.pack('<HHHHHHB', FAST_PULSE, 250, 499, ZERO, ONE, FAST_LEADER, 8)
    out += struct.pack('<H', 0)
    out += len(data).to_bytes(3, 'little')
    out += data


def emit_fast_payload(out, g, number):
    if g['pause']:
        raise ValueError(f'fast payload {number} has a pause')
    if g['totp'] != 1 or len(g['psyms']) != 1 or g['psyms'][0] != [501]:
        raise ValueError(f'fast payload {number} minisync is not 501')
    if len(g['dsyms']) < 2 or g['dsyms'][0][0] != ZERO or g['dsyms'][1][0] != ONE:
        raise ValueError(f'fast payload {number} data timing is not {ZERO}/{ONE}')

    data = g['raw']
    out.append(0x12)
    out += struct.pack('<HH', 501, 1)
    out.append(0x14)
    out += struct.pack('<HHB', ZERO, ONE, 8)
    out += struct.pack('<H', 0)
    out += len(data).to_bytes(3, 'little')
    out += data


def convert(src, dst):
    d = open(src, 'rb').read()
    if d[:8] != b'ZXTape!\x1a':
        raise ValueError('bad TZX header')

    out = bytearray(d[:10])
    o = 10
    rom_index = 0
    fast_part = 0
    removed_pauses = 0

    while o < len(d):
        bid = d[o]
        o += 1

        if bid == 0x13:
            pulses = []
            while True:
                n = d[o]
                pulses.extend(u16(d, o + 1 + 2*k) for k in range(n))
                o += 1 + 2*n
                if o >= len(d) or d[o] != 0x13:
                    break
                o += 1
            emit_pulses(out, shorten_legacy_pulses(pulses))
            continue

        ln = block_len(d, o, bid)
        if bid == 0x19:
            g = parse_gdb(d[o:o + ln])
            if not g['totd']:
                pass
            elif fast_part % 2 == 0:
                emit_fast_header(out, g, fast_part // 2 + 1)
                fast_part += 1
            else:
                emit_fast_payload(out, g, fast_part // 2 + 1)
                fast_part += 1
        elif bid == 0x20:
            removed_pauses += 1
        elif bid == 0x11:
            body = bytearray(d[o:o + ln])
            if rom_index >= len(ROM_PILOTS):
                raise ValueError('unexpected extra ROM turbo block')
            got = u16(body, 10)
            want = ROM_PILOTS[rom_index]
            if got != want:
                raise ValueError(f'ROM pilot {rom_index + 1} is {got}, expected {want}')
            rom_index += 1
            struct.pack_into('<H', body, 13, 0)
            out += bytes([bid]) + body
        elif bid == 0x10:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 0, 0)
            out += bytes([bid]) + body
        elif bid == 0x14:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 5, 0)
            out += bytes([bid]) + body
        elif bid == 0x15:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 2, 0)
            out += bytes([bid]) + body
        else:
            out += bytes([bid]) + d[o:o + ln]
        o += ln

    if rom_index != len(ROM_PILOTS):
        raise ValueError(f'expected {len(ROM_PILOTS)} ROM turbo blocks, saw {rom_index}')
    if fast_part != 4:
        raise ValueError(f'expected four fast parts, saw {fast_part}')

    open(dst, 'wb').write(out)
    print(f"{dst}: compact standard turbo blocks, {len(out)} bytes, "
          f"{removed_pauses} pause block(s) removed")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: tzx19to13.py IN.tzx OUT.tzx')
    convert(sys.argv[1], sys.argv[2])
