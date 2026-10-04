#!/usr/bin/env python3
"""Focused assembled checks for unbiased bounded random reduction."""
import argparse
import re

from skoolkit import CSimulator
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, B, C, SP, PC
from skoolkit.trace import Tracer


DIVISORS = (4, 7, 9, 11, 13, 24)


def load_symbols(path):
    symbols = {}
    with open(path, encoding='utf-8') as src:
        for line in src:
            parts = line.replace(':', '').split()
            if len(parts) < 3 or parts[1].upper() != 'EQU':
                continue
            value = parts[2]
            if value.lower().startswith('0x'):
                symbols[parts[0]] = int(value, 16)
            elif value.upper().endswith('H'):
                symbols[parts[0]] = int(value[:-1], 16)
            else:
                symbols[parts[0]] = int(value, 0)
    return symbols


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--snap', required=True)
    ap.add_argument('--sym', required=True)
    ap.add_argument('--source', required=True)
    args = ap.parse_args()
    sym = load_symbols(args.sym)
    required = ('rand', 'rand_n', 'seed')
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('random-bounds check missing symbols: ' + ', '.join(missing))

    source = open(args.source, encoding='utf-8').read()
    literal = {int(x) for x in re.findall(r'ld\s+c\s*,\s*(\d+)\s*\n\s*call\s+rand_n', source, re.I)}
    m = re.search(r'PROFILES:\s*(.*?)PF_WC', source, re.S)
    if not m:
        raise SystemExit('random-bounds check failed: profile table not found')
    jitters = [
        int(x) for x in re.findall(
            r'db\s+[^\n]+\s*\n\s*dw\s+[^\n]+\s*\n\s*db\s+[^,\n]+,[^,\n]+,(\d+)',
            m.group(1), re.I
        )
    ]
    if len(jitters) != 4:
        raise SystemExit('random-bounds check failed: profile table is incomplete')
    dynamic = {2 * radius + 1 for radius in jitters}
    used = literal | dynamic
    if used != set(DIVISORS) or 0 in used:
        raise SystemExit(f'random-bounds check failed: call-site divisors are {sorted(used)}')

    snap = Snapshot.get(args.snap)
    sim = from_snapshot(CSimulator, snap, {}, {'ay': [None] * 16},
                        {'fast_djnz': False, 'fast_ldir': False})
    tracer = Tracer(sim, snap.border, 0, 0, list(snap.ay), snap.outfe, False)
    sim.set_tracer(tracer)
    mem = sim.memory
    regs = sim.registers

    def check(condition, message):
        if not condition:
            raise SystemExit('random-bounds check failed: ' + message)

    def call_rand_n(divisor, max_tstates=500000):
        sentinel = 0x7EFE
        regs[C] = divisor
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(sym['rand_n'], sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        check(regs[PC] == sentinel, f'rand_n did not return for C={divisor}')
        return regs[1] & 255  # A

    # Same seed and divisor must produce the same bounded sequence.
    for divisor in DIVISORS:
        seqs = []
        for _ in range(2):
            mem[sym['seed']] = 0x34
            mem[sym['seed'] + 1] = 0x12
            seqs.append([call_rand_n(divisor) for _ in range(64)])
        check(seqs[0] == seqs[1], f'C={divisor} is not repeatable from one seed')
        check(all(0 <= x < divisor for x in seqs[0]), f'C={divisor} escaped its range')

    # Replace rand with a tiny source reader. It walks bytes from a pointer in low RAM.
    ptr = 0x7F00
    data = 0x7F20
    patch = [
        0x2A, ptr & 255, ptr >> 8,       # LD HL,(ptr)
        0x7E,                            # LD A,(HL)
        0x23,                            # INC HL
        0x22, ptr & 255, ptr >> 8,       # LD (ptr),HL
        0x6F,                            # LD L,A
        0x26, 0x00,                      # LD H,0
        0xC9,                            # RET
    ]
    rand_addr = sym['rand']
    saved = list(mem[rand_addr:rand_addr + len(patch)])
    mem[rand_addr:rand_addr + len(patch)] = patch

    for divisor in DIVISORS:
        limit = (128 // divisor) * divisor
        stream = list(range(128)) + list(range(128))
        mem[data:data + len(stream)] = stream
        mem[ptr] = data & 255
        mem[ptr + 1] = data >> 8
        counts = [0] * divisor
        while True:
            before = mem[ptr] | (mem[ptr + 1] << 8)
            if before >= data + 128:
                break
            value = call_rand_n(divisor)
            after = mem[ptr] | (mem[ptr + 1] << 8)
            if after > data + 128:
                break
            counts[value] += 1
        expected = 128 // divisor
        check(counts == [expected] * divisor,
              f'C={divisor} synthetic cycle buckets are {counts}')

        if limit < 128:
            mem[data] = limit
            mem[data + 1] = 3
            mem[ptr] = data & 255
            mem[ptr + 1] = data >> 8
            value = call_rand_n(divisor)
            after = mem[ptr] | (mem[ptr + 1] << 8)
            check(after == data + 2, f'C={divisor} did not redraw rejected tail')
            check(value == 3 % divisor, f'C={divisor} redraw returned {value}')

    mem[rand_addr:rand_addr + len(saved)] = saved
    print('random-bounds assembled checks: PASS')


if __name__ == '__main__':
    main()
