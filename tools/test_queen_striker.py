#!/usr/bin/env python3
"""Focused assembled checks for Queen + own coin + striker continuation."""
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
        'new_match', 'setup_board', 'ph_resolve', 'stats_stroke', 'PH_NEWBOARD',
        'phase', 'break_made', 'seat', 'white_pair',
        'pk_count', 'pk_ids', 'left', 'dues', 'qstate', 'qpend', 'rcont',
        'BODIES', 'BSZ', 'BF', 'F_ON', 'QUEEN', 'STRIKER', 'FREESPOTS',
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
            raise SystemExit('queen-striker check failed: ' + message)

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

    def fresh(left_count):
        check(call_routine(sym['new_match']), 'new_match did not return')
        check(call_routine(sym['setup_board']), 'setup_board did not return')
        mem[sym['break_made']] = 1
        mem[sym['seat']] = 0
        mem[sym['white_pair']] = 0
        mem[sym['left']] = left_count
        mem[sym['dues']] = 0
        mem[sym['qstate']] = 0
        mem[sym['qpend']] = 0

    def pocket(ids):
        mem[sym['pk_count']] = len(ids)
        for i, piece in enumerate(ids):
            mem[sym['pk_ids'] + i] = piece
            if piece != sym['STRIKER']:
                mem[body_addr(piece) + sym['BF']] = 0

    # All nine own coins began on the board: own coin is forced back, Due remains owed, turn continues.
    fresh(9)
    pocket([sym['QUEEN'], 0, sym['STRIKER']])
    check(run_to(sym['ph_resolve'], sym['stats_stroke']), 'full-set combination did not reach accounting')
    check(mem[sym['qstate']] == 0 and (mem[body_addr(sym['QUEEN']) + sym['BF']] & sym['F_ON']),
          'Queen was not returned physically')
    check(mem[sym['left']] == 9 and (mem[body_addr(0) + sym['BF']] & sym['F_ON']),
          'own pocketed coin was not returned')
    check(mem[sym['dues']] == 1, 'required Due was not left owed when no spare pocketed coin existed')
    check(mem[sym['rcont']] == 1, 'full-set Queen+own+striker did not continue')

    # With a spare previously pocketed coin, both the forced coin and the Due can be returned.
    fresh(8)
    mem[body_addr(1) + sym['BF']] = 0
    pocket([sym['QUEEN'], 0, sym['STRIKER']])
    check(run_to(sym['ph_resolve'], sym['stats_stroke']), 'reduced-set combination did not reach accounting')
    check(mem[sym['left']] == 9, 'forced return plus Due did not restore two own coins')
    check(mem[sym['dues']] == 0, 'Due remained after a spare pocketed coin was returned')
    check(mem[sym['rcont']] == 1, 'reduced-set Queen+own+striker did not continue')

    # Queen + striker with no own coin is a different rule and must not inherit continuation.
    fresh(9)
    pocket([sym['QUEEN'], sym['STRIKER']])
    check(run_to(sym['ph_resolve'], sym['stats_stroke']), 'Queen+striker-only case did not reach accounting')
    check(mem[sym['rcont']] == 0, 'Queen+striker-only incorrectly continued')

    # Controlled placement fault: no Queen spot means no fake return state.
    fresh(9)
    pocket([sym['QUEEN'], 0, sym['STRIKER']])
    mem[sym['FREESPOTS']] = 128
    check(call_routine(sym['ph_resolve']), 'placement-fault resolver did not return')
    check(mem[sym['phase']] == sym['PH_NEWBOARD'], 'placement fault did not schedule clean replay')
    check(mem[sym['qstate']] != 0, 'Queen state claims a successful return after placement fault')
    check(not (mem[body_addr(sym['QUEEN']) + sym['BF']] & sym['F_ON']), 'Queen body was marked on-board without placement')
    check(mem[sym['left']] == 8, 'own coin count claims a failed forced return succeeded')
    check(mem[sym['dues']] == 1, 'Due state claims payment after placement fault')

    print('queen-striker assembled checks: PASS')


if __name__ == '__main__':
    main()
