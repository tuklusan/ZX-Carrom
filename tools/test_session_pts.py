#!/usr/bin/env python3
"""Focused assembled checks for session PTS by coin ownership."""
import argparse

from skoolkit import CSimulator
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, F, SP, PC
from skoolkit.trace import Tracer


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
    args = ap.parse_args()
    sym = load_symbols(args.sym)
    required = (
        'stats_stroke', 'stats_board', 'stats_clear', 'stats_second_call',
        'score', 'rn', 'rm', 'rcA', 'rA', 'rret', 'white_pair',
    )
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('session-PTS check missing symbols: ' + ', '.join(missing))

    snap = Snapshot.get(args.snap)
    sim = from_snapshot(CSimulator, snap, {}, {'ay': [None] * 16},
                        {'fast_djnz': False, 'fast_ldir': False})
    tracer = Tracer(sim, snap.border, 0, 0, list(snap.ay), snap.outfe, False)
    sim.set_tracer(tracer)
    mem = sim.memory
    regs = sim.registers

    def check(condition, message):
        if not condition:
            raise SystemExit('session-PTS check failed: ' + message)

    def call_routine(addr, max_tstates=500000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        check(regs[PC] == sentinel, 'routine did not return')
        return bool(regs[F] & 1)

    def set_points(p0, p1):
        mem[sym['score']] = p0 % 100
        mem[sym['score'] + 1] = p1 % 100
        mem[sym['score'] + 2] = p0 // 100
        mem[sym['score'] + 3] = p1 // 100

    def points(pair):
        return mem[sym['score'] + pair] + 100 * mem[sym['score'] + 2 + pair]

    def stroke(own, opp, ret0=0, ret1=0, mover_pair=0, mover_colour=0, white_pair=0):
        mem[sym['rn']] = own
        mem[sym['rm']] = opp
        mem[sym['rret']] = ret0
        mem[sym['rret'] + 1] = ret1
        mem[sym['rA']] = mover_pair
        mem[sym['rcA']] = mover_colour
        mem[sym['white_pair']] = white_pair
        return call_routine(sym['stats_stroke'])

    set_points(0, 0)
    check(not stroke(0, 1), 'opponent-colour credit signalled overflow')
    check((points(0), points(1)) == (0, 1),
          'opponent-colour pocket did not credit its owning pair')

    set_points(0, 0)
    check(not stroke(1, 1), 'mixed-colour credit signalled overflow')
    check((points(0), points(1)) == (1, 1),
          'mixed-colour pocket did not credit both owners')

    set_points(0, 2)
    check(not stroke(0, 0, ret1=1), 'return subtraction signalled overflow')
    check((points(0), points(1)) == (0, 1),
          'returned black coin did not debit black owner')

    set_points(0, 4)
    check(not stroke(0, 1, ret1=1), 'same-stroke net signalled overflow')
    check(points(1) == 4, 'pocket then return of one colour did not net to zero')

    set_points(5, 0)
    mem[sym['rret']] = 7
    mem[sym['rret'] + 1] = 8
    mem[sym['rn']] = 1
    mem[sym['rm']] = 0
    mem[sym['rA']] = 0
    mem[sym['rcA']] = 0
    mem[sym['white_pair']] = 0
    check(not call_routine(sym['stats_board']), 'board-end accounting signalled overflow')
    check((points(0), points(1)) == (6, 0),
          'board-end accounting consumed stale normal-stroke returns')

    set_points(0, 0)
    check(not stroke(0, 0, ret1=1), 'underflow case signalled overflow')
    check(points(1) == 0, 'score subtraction underflowed')

    set_points(0, 0)
    check(not stroke(0, 1, mover_pair=0, mover_colour=1, white_pair=1),
          'remapped colour credit signalled overflow')
    check((points(0), points(1)) == (0, 1),
          'colour ownership mapping followed the mover instead of the coin')

    set_points(999, 0)
    check(stroke(1, 0), '999+1 did not signal bounded-counter overflow')
    check(call_routine(sym['stats_clear']) is False, 'stats_clear returned carry')
    check(all(mem[sym['score'] + i] == 0 for i in range(4)),
          'bounded-counter reset did not clear PTS')

    set_points(0, 0)
    mem[sym['rn']] = 0
    mem[sym['rm']] = 1
    mem[sym['rret']] = 0
    mem[sym['rret'] + 1] = 0
    mem[sym['rA']] = 0
    mem[sym['rcA']] = 0
    mem[sym['white_pair']] = 0
    p = sym['stats_second_call']
    saved = list(mem[p:p + 3])
    mem[p:p + 3] = [0xC9, 0x00, 0x00]
    check(not call_routine(sym['stats_stroke']), 'controlled fixture signalled overflow')
    check((points(0), points(1)) == (0, 0),
          'controlled old fixture did not reproduce missing opponent credit')
    mem[p:p + 3] = saved

    print('session-PTS assembled checks: PASS')


if __name__ == '__main__':
    main()
