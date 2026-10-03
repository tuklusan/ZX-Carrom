#!/usr/bin/env python3
"""Finalize the turbo TZX as explicit pulse-sequence blocks.

- expands generalized-data blocks so the release file is the exact stream used
  by cycle-level runtime checks;
- normalizes each fast leader to 256 pulses at 1710 T-states;
- preserves the cold-loadable ROM-loader turbo-data pilots;
- removes explicit pause blocks and forces data-block pauses to 0 ms.
"""
import sys, struct

ROM_PILOTS = [2824, 2420]
SHORT_FAST_LEADER = 256
FAST_LEADER_PULSE = 1710
EXPECTED_FAST_LEADERS = 2


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
        return pulses, False
    first = pulses[0]
    run = 1
    while run < len(pulses) and pulses[run] == first:
        run += 1
    if run >= limit:
        return [FAST_LEADER_PULSE] * limit + pulses[run:], True
    return pulses, False


def emit_pulses(out, pulses):
    for i in range(0, len(pulses), 255):
        chunk = pulses[i:i + 255]
        out += bytes([0x13, len(chunk)]) + b''.join(struct.pack('<H', x) for x in chunk)


def patch_compact_leader(body):
    """Patch one generalized fast-header leader in place; return True if found."""
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


def gdb_pulses(body):
    if len(body) < 18:
        raise ValueError('short generalized-data block')
    totp, npp, asp = u32(body, 6), body[10], body[11] or 256
    totd, npd, asd = u32(body, 12), body[16], body[17] or 256
    p = 18

    psyms = []
    for _ in range(asp if totp else 0):
        if p + 1 + 2 * npp > len(body):
            raise ValueError('truncated generalized pilot symbols')
        if body[p] & 3:
            raise ValueError('unsupported generalized pilot symbol type')
        vals = [u16(body, p + 1 + 2 * k) for k in range(npp)]
        psyms.append([x for x in vals if x])
        p += 1 + 2 * npp

    pulses = []
    for _ in range(totp):
        if p + 3 > len(body):
            raise ValueError('truncated generalized pilot sequence')
        sym, rep = body[p], u16(body, p + 1)
        p += 3
        pulses.extend(psyms[sym] * rep)

    dsyms = []
    for _ in range(asd if totd else 0):
        if p + 1 + 2 * npd > len(body):
            raise ValueError('truncated generalized data symbols')
        if body[p] & 3:
            raise ValueError('unsupported generalized data symbol type')
        vals = [u16(body, p + 1 + 2 * k) for k in range(npd)]
        dsyms.append([x for x in vals if x])
        p += 1 + 2 * npd

    if totd:
        bits = max(1, (asd - 1).bit_length())
        bitpos = 0
        for _ in range(totd):
            sym = 0
            for _ in range(bits):
                byte = body[p + bitpos // 8]
                sym = (sym << 1) | ((byte >> (7 - bitpos % 8)) & 1)
                bitpos += 1
            pulses.extend(dsyms[sym])
    return pulses


def convert(src, dst):
    d = open(src, 'rb').read()
    if d[:8] != b'ZXTape!\x1a':
        raise ValueError('bad TZX header')
    out = bytearray(d[:10])
    o = 10
    n19 = n19skip = n20 = n11 = n13 = 0
    fast_leaders = 0
    rom_index = 0

    while o < len(d):
        bid = d[o]
        o += 1

        if bid == 0x13:
            pulses = []
            while True:
                n = d[o]
                pulses.extend(u16(d, o + 1 + 2 * k) for k in range(n))
                o += 1 + 2 * n
                n13 += 1
                if o >= len(d) or d[o] != 0x13:
                    break
                o += 1
            pulses, changed = shorten_legacy_pulses(pulses)
            fast_leaders += int(changed)
            emit_pulses(out, pulses)
            continue

        ln = block_len(d, o, bid)
        if bid == 0x19:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 4, 0)
            if u32(body, 12) == 0:
                n19skip += 1
            else:
                fast_leaders += int(patch_compact_leader(body))
                emit_pulses(out, gdb_pulses(body))
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
        elif bid == 0x15:
            body = bytearray(d[o:o + ln])
            struct.pack_into('<H', body, 2, 0)
            out += bytes([bid]) + body
        else:
            out += bytes([bid]) + d[o:o + ln]
        o += ln

    if rom_index != len(ROM_PILOTS):
        raise ValueError(f'expected {len(ROM_PILOTS)} ROM turbo blocks, saw {rom_index}')
    if fast_leaders != EXPECTED_FAST_LEADERS:
        raise ValueError(f'expected {EXPECTED_FAST_LEADERS} fast leaders, saw {fast_leaders}')
    open(dst, 'wb').write(out)
    print(f"{dst}: {n11} ROM blocks, {n19} generalized block(s) expanded, "
          f"{n13} legacy pulse block(s) normalized, {n20} pause block(s) removed, "
          f"{n19skip} timing-only generalized block(s) removed, "
          f"{fast_leaders} fast leader(s) normalized")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: tzx19to13.py IN.tzx OUT.tzx')
    convert(sys.argv[1], sys.argv[2])
