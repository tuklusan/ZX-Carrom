#!/usr/bin/env python3
"""Focused assembled checks for two-colour Due recovery."""
import argparse

from skoolkit import CSimulator
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, SP, PC
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
        'new_match', 'setup_board', 'ph_resolve', 'stats_stroke',
        'break_made', 'seat', 'white_pair', 'pk_count', 'pk_ids',
        'left', 'dues', 'rret', 'due_other_call',
        'BODIES', 'BSZ', 'BF', 'F_ON',
    )
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('missing symbols: ' + ', '.join(missing))

    snap = Snapshot.get(args.snap)
    sim = from_snapshot(CSimulator, snap, {}, {'ay': [None] * 16},
                        {'fast_djnz': False, 'fast_ldir': False})
    tracer = Tracer(sim, snap.border, 0, 0, list(snap.ay), snap.outfe, False)
    sim.set_tracer(tracer)
    mem = sim.memory
    regs = sim.registers

    def check(condition, message):
        if not condition:
            raise SystemExit('due-recovery check failed: ' + message)

    def call_routine(addr, max_tstates=1000000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == sentinel

    def run_to(addr, stop, max_tstates=2500000):
        tracer.run(addr, stop, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == stop

    def body_addr(piece):
        return sym['BODIES'] + piece * sym['BSZ']

    def on_board(piece):
        return bool(mem[body_addr(piece) + sym['BF']] & sym['F_ON'])

    def fresh():
        check(call_routine(sym['new_match']), 'new_match did not return')
        check(call_routine(sym['setup_board']), 'setup_board did not return')
        mem[sym['break_made']] = 1
        mem[sym['seat']] = 0
        mem[sym['white_pair']] = 0
        mem[sym['left']] = 9
        mem[sym['left'] + 1] = 9
        mem[sym['dues']] = 0
        mem[sym['dues'] + 1] = 0
        mem[sym['pk_count']] = 0

    def pocket(ids):
        mem[sym['pk_count']] = len(ids)
        for i, piece in enumerate(ids):
            mem[sym['pk_ids'] + i] = piece
            mem[body_addr(piece) + sym['BF']] = 0

    def resolve():
        check(run_to(sym['ph_resolve'], sym['stats_stroke']),
              'resolver did not reach accounting')

    # Non-moving colour Due becomes payable when that colour is pocketed.
    fresh()
    mem[sym['dues'] + 1] = 1
    pocket([9])
    resolve()
    check(mem[sym['dues'] + 1] == 0, 'other-colour Due was not paid')
    check(mem[sym['left'] + 1] == 9, 'other-colour return did not restore left count')
    check(on_board(9), 'returned body was not from the owing colour')
    check(mem[sym['rret'] + 1] == 1, 'other-colour physical return count is wrong')

    # Both colours can settle independently in one stroke.
    fresh()
    mem[sym['dues']] = 1
    mem[sym['dues'] + 1] = 1
    pocket([0, 9])
    resolve()
    check(mem[sym['dues']] == 0 and mem[sym['dues'] + 1] == 0,
          'two-colour Dues did not settle independently')
    check(mem[sym['left']] == 9 and mem[sym['left'] + 1] == 9,
          'two-colour returns produced wrong left counts')
    check(on_board(0) and on_board(9), 'returned body colour is wrong')
    check(mem[sym['rret']] == 1 and mem[sym['rret'] + 1] == 1,
          'per-colour return counts are wrong')

    # No pocketed B coin means no fabricated return and the Due stays.
    fresh()
    mem[sym['dues'] + 1] = 1
    resolve()
    check(mem[sym['dues'] + 1] == 1, 'unpayable other-colour Due was cleared')
    check(mem[sym['left'] + 1] == 9, 'on-board other-colour coin was removed')
    check(mem[sym['rret'] + 1] == 0, 'unpayable Due reported a physical return')

    # Paying B must not consume A's Due or an A body.
    fresh()
    mem[sym['dues']] = 1
    mem[sym['dues'] + 1] = 1
    pocket([9])
    resolve()
    check(mem[sym['dues']] == 1 and mem[sym['dues'] + 1] == 0,
          'one colour changed the other colour Due')
    check(mem[sym['left']] == 9 and on_board(0),
          'paying B returned or removed an A coin')
    check(mem[sym['left'] + 1] <= 9, 'left count exceeded nine')

    # Controlled old-behaviour fixture: skip only the non-moving-colour call.
    fresh()
    mem[sym['dues'] + 1] = 1
    pocket([9])
    call = sym['due_other_call']
    mem[call:call + 3] = [0, 0, 0]
    resolve()
    check(mem[sym['dues'] + 1] == 1 and mem[sym['left'] + 1] == 8 and not on_board(9),
          'controlled old fixture did not expose the original defect')

    print('due-recovery assembled checks: PASS')


if __name__ == '__main__':
    main()
