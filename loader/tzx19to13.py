#!/usr/bin/env python3
"""Finalize the compact turbo TZX.

- preserves generalized-data blocks instead of expanding every edge;
- patches the first fast leader to 256 pulses at 1710 T-states;
- preserves the cold-loadable ROM-loader turbo-data pilots;
- removes explicit pause blocks and forces data-block pauses to 0 ms.
"""
import sys, struct

ROM_PILOTS = [2824, 2420]
SHORT_FAST_LEADER = 256
FAST_LEADER_PULSE = 1710

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]

def block_len(d, o, bid):
    if bid == 0x10: return 4 + u16(d, o + 2)
    if bid == 0x11: return 18 + (u32(d, o + 15) & 0xFFFFFF)
    if bid == 0x12: return 4
    if bid == 0x13: return 1 + 2 * d[o]
    if bid == 0x14: return 10 + (u32(d, o + 7) & 0xFFFFFF)
    if bid == 0x15: return 8 + (u32(d, o + 5) & 0xFFFFFF)
    if bid == 0x19: return 4 + u32(d, o)
    if bid == 0x20: return 2
    if bid in (0x21, 0x30): return 1 + d[o]
    if bid == 0x22: return 0
    if bid == 0x32: return 2 + u16(d, o)
    if bid == 0x5A: return 9
    raise ValueError(f"TZX block 0x{bid:02X} not handled")

def shorten_legacy_pulses(pulses, limit=SHORT_FAST_LEADER):
    if not pulses:
        return pulses
    first = pulses[0]
    run = 1
    while run < len(pulses) and pulses[run] == first:
        run += 1
    if run >= limit:
        return [FAST_LEADER_PULSE] * limit + pulses[run:]
    return pulses

def emit_pulses(out, pulses):
    for i in range(0, len(pulses), 255):
        chunk = pulses[i:i + 255]
        out += bytes([0x13, len(chunk)]) + b''.join(struct.pack('<H', x) for x in chunk)

def patch_compact_leader(body):
    """Patch a ZQLoader generalized header block in place; return True if found."""
    if len(body) < 18:
        return False
    struct.pack_into('<H', body, 4, 0)
    totp = u32(body, 6)
    npp = body[10]
    asp = body[11] or 256
    totd = u32(body, 12)
    if totp < 2 or npp < 1 or asp < 2 or not totd:
        return False

    p = 18
    defs = []
    for _ in range(asp):
        if p + 1 + 2 * npp > len(body):
            raise ValueError('truncated generalized pilot table')
        vals = [u16(body, p + 1 + 2 * k) for k in range(npp)]
        defs.append((p, vals))
        p += 1 + 2 * npp
    if p + 3 * totp > len(body):
        raise ValueError('truncated generalized pilot stream')

    sym = body[p]
    rep = u16(body, p + 1)
    vals = [v for v in defs[sym][1] if v]
    if sym != 0 or not vals or rep * len(vals) < SHORT_FAST_LEADER:
        return False
    if SHORT_FAST_LEADER % len(vals):
        raise ValueError('leader symbol width does not divide requested pulse count')

    dpos = defs[0][0]
    for k, v in enumerate(defs[0][1]):
        if v:
            struct.pack_into('<H', body, dpos + 1 + 2 * k, FAST_LEADER_PULSE)
    struct.pack_into('<H', body, p + 1, SHORT_FAST_LEADER // len(vals))
    return True

def convert(src, dst):
    d = open(src, 'rb').read()
    assert d[:8] == b'ZXTape!\x1a'
    out = bytearray(d[:10])
    o = 10
    n19 = n19wait = n20 = n11 = n13 = 0
    fast_leader_done = False
    fast_leaders = 0
    rom_index = 0

    while o < len(d):
        bid = d[o]; o += 1

        if bid == 0x13 and not fast_leader_done:
            pulses = []
            while True:
                n = d[o]
                pulses.extend(u16(d, o + 1 + 2 * k) for k in range(n))
                o += 1 + 2 * n
                n13 += 1
                if o >= len(d) or d[o] != 0x13:
                    break
                o += 1
            pulses = shorten_legacy_pulses(pulses)
            emit_pulses(out, pulses)
            fast_leader_done = True
            continue

        ln = block_len(d, o, bid)
        if bid == 0x19:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 4, 0)
            if u32(body, 12) == 0:
                n19wait += 1
            else:
                if patch_compact_leader(body):
                    fast_leader_done = True
                    fast_leaders += 1
                out += bytes([bid]) + body
                n19 += 1
        elif bid == 0x20:
            n20 += 1
        elif bid == 0x11:
            body = bytearray(d[o:o + ln])
            if rom_index >= len(ROM_PILOTS):
                raise ValueError('unexpected extra ROM turbo block')
            pilot_count = u16(body, 10)
            expected = ROM_PILOTS[rom_index]
            if pilot_count != expected:
                raise ValueError(f'ROM pilot {rom_index + 1} is {pilot_count}, expected {expected}')
            rom_index += 1
            struct.pack_into('<H', body, 13, 0)
            out += bytes([bid]) + body
            n11 += 1
        elif bid == 0x10:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 0, 0)
            out += bytes([bid]) + body
        elif bid == 0x14:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 5, 0)
            out += bytes([bid]) + body
        else:
            out += bytes([bid]) + d[o:o + ln]
        o += ln

    if rom_index != len(ROM_PILOTS):
        raise ValueError(f'expected {len(ROM_PILOTS)} ROM turbo blocks, saw {rom_index}')
    if not fast_leader_done:
        raise ValueError('fast leader not found')
    open(dst, 'wb').write(out)
    print(f"{dst}: {n11} ROM blocks, {n19} compact generalized block(s), "
          f"{n13} legacy pulse block(s), {n20} pause block(s) removed, "
          f"{n19wait} timing-only generalized wait(s) removed, "
          f"{fast_leaders} compact fast leader(s) normalized")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: tzx19to13.py IN.tzx OUT.tzx')
    convert(sys.argv[1], sys.argv[2])
