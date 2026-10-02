#!/usr/bin/env python3
"""Finalize ZQLoader TZX output for Carrom Arena.

- expands generalized-data (0x19) blocks into portable pulse-sequence (0x13) blocks;
- shortens every ROM-loader turbo-data pilot to SHORT_ROM_PILOT pulses;
- shortens the leading 2x ZQLoader pulse train to SHORT_FAST_LEADER pulses;
- removes every explicit pause block and forces per-block pauses to 0 ms.

The result is a continuous tape image with short headers and no inserted silence.
"""
import sys, struct

SHORT_ROM_PILOT = 512
SHORT_FAST_LEADER = 256
FAST_LEADER_PULSE = 10000

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

def gdb_pulses(d, o):
    totp, npp, asp = u32(d, o + 6), d[o + 10], d[o + 11] or 256
    totd, npd, asd = u32(d, o + 12), d[o + 16], d[o + 17] or 256
    p = o + 18
    pulses = []
    def symdef(p, n, count):
        syms = []
        for _ in range(count):
            flag = d[p]
            assert flag & 3 == 0, "only edge-toggling symbols are supported"
            ln = [u16(d, p + 1 + 2 * k) for k in range(n)]
            syms.append([x for x in ln if x] if 0 not in ln else ln[:ln.index(0)])
            p += 1 + 2 * n
        return syms, p
    if totp:
        psyms, p = symdef(p, npp, asp)
        for _ in range(totp):
            s, rep = d[p], u16(d, p + 1)
            p += 3
            pulses += psyms[s] * rep
    if totd:
        dsyms, p = symdef(p, npd, asd)
        nb = max(1, (asd - 1).bit_length())
        bitpos = 0
        for _ in range(totd):
            v = 0
            for _ in range(nb):
                byte = d[p + bitpos // 8]
                v = (v << 1) | ((byte >> (7 - bitpos % 8)) & 1)
                bitpos += 1
            pulses += dsyms[v]
    return pulses

def shorten_leader(pulses, limit=SHORT_FAST_LEADER):
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

def convert(src, dst):
    d = open(src, 'rb').read()
    assert d[:8] == b'ZXTape!\x1a'
    out = bytearray(d[:10])
    o = 10
    n19 = n20 = n11 = n13 = 0
    fast_leader_done = False

    while o < len(d):
        bid = d[o]; o += 1

        # ZQLoader output may already contain ID 0x13 pulse blocks.  Gather the
        # entire first contiguous pulse stream so the leader can be shortened
        # across 255-pulse TZX chunk boundaries, rather than only inside one
        # chunk.  This was the subtle reason a nominal 256-pulse setting could
        # still leave ~1400 identical leader pulses in an already-expanded TZX.
        if bid == 0x13 and not fast_leader_done:
            pulses = []
            while True:
                n = d[o]
                pulses.extend(u16(d, o + 1 + 2 * k) for k in range(n))
                o += 1 + 2 * n
                n13 += 1
                if o >= len(d) or d[o] != 0x13:
                    break
                o += 1                         # consume next 0x13 id
            pulses = shorten_leader(pulses)
            emit_pulses(out, pulses)
            fast_leader_done = True
            continue

        ln = block_len(d, o, bid)
        if bid == 0x19:
            pulses = gdb_pulses(d, o)
            if not fast_leader_done:
                pulses = shorten_leader(pulses)
                fast_leader_done = True
            emit_pulses(out, pulses)
            n19 += 1
        elif bid == 0x20:
            n20 += 1                     # deliberately omit all silent gaps
        elif bid == 0x11:
            body = bytearray(d[o:o + ln])
            pilot_count = u16(body, 10)
            struct.pack_into('<H', body, 10, min(pilot_count, SHORT_ROM_PILOT))
            struct.pack_into('<H', body, 13, 0)  # zero post-block pause
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
    open(dst, 'wb').write(out)
    print(f"{dst}: {n11} ROM blocks shortened, {n19} generalized fast block(s) expanded, "
          f"{n13} existing pulse block(s) normalized, {n20} pause block(s) removed")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: tzx19to13.py IN.tzx OUT.tzx')
    convert(sys.argv[1], sys.argv[2])
