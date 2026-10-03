#!/usr/bin/env python3
"""Focused assembled checks for board-long coin-colour pocket history."""
import argparse

from skoolkit import CSimulator
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, A, F, SP, PC
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
        'new_match', 'setup_board', 'ph_resolve', 'stats_stroke', 'ai_begin',
        'ai_tn', 'ai_t', 'had', 'dues', 'pk_count', 'pk_ids',
        'break_made', 'seat', 'white_pair', 'BODIES', 'BSZ', 'BF',
        'F_ON', 'left', 'qstate', 'QUEEN', 'STRIKER',
    )
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('missing symbols: ' + ', '.join(missing))

    snap = Snapshot.get(args.snap)
    sim = from_snapshot(
        CSimulator, snap, {}, {'ay': [None] * 16},
        {'fast_djnz': False, 'fast_ldir': False},
    )
    tracer = Tracer(sim, snap.border, 0, 0, list(snap.ay), snap.outfe, False)
    sim.set_tracer(tracer)
    mem = sim.memory
    regs = sim.registers

    def check(condition, message):
        if not condition:
            raise SystemExit('queen-history check failed: ' + message)

    def call_routine(addr, max_ops=750000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_ops, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == sentinel

    def run_to(addr, stop, max_tstates=2000000):
        tracer.run(addr, stop, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == stop

    def body_addr(coin_id):
        return sym['BODIES'] + coin_id * sym['BSZ']

    def fresh_board():
        check(call_routine(sym['new_match']), 'new_match did not return')
        check(call_routine(sym['setup_board']), 'setup_board did not return')
        mem[sym['break_made']] = 1
        mem[sym['seat']] = 0
        mem[sym['white_pair']] = 0
        mem[sym['pk_count']] = 0
        mem[sym['had']] = 0
        mem[sym['had'] + 1] = 0
        mem[sym['dues']] = 0
        mem[sym['dues'] + 1] = 0
        mem[sym['qstate']] = 0

    def queen_is_targeted():
        check(call_routine(sym['ai_begin']), 'planner target setup did not return')
        count = mem[sym['ai_tn']]
        targets = list(mem[sym['ai_t']:sym['ai_t'] + count])
        return sym['QUEEN'] in targets

    # Side A pockets a side-B coin: history belongs to the coin colour, not the mover.
    fresh_board()
    mem[sym['pk_count']] = 1
    mem[sym['pk_ids']] = 9
    mem[body_addr(9) + sym['BF']] = 0
    check(run_to(sym['ph_resolve'], sym['stats_stroke']), 'opponent-colour resolve did not reach accounting')
    check(mem[sym['had']] == 0 and mem[sym['had'] + 1] == 1,
          'opponent-colour pocket did not record that colour')

    # Own coin plus striker: the forced return must not erase the pocket history.
    fresh_board()
    mem[sym['pk_count']] = 2
    mem[sym['pk_ids']] = 0
    mem[sym['pk_ids'] + 1] = sym['STRIKER']
    mem[body_addr(0) + sym['BF']] = 0
    check(run_to(sym['ph_resolve'], sym['stats_stroke']), 'striker-return resolve did not reach accounting')
    check(mem[sym['had']] == 1, 'own coin plus striker lost pocket history')
    check(mem[sym['left']] == 9, 'forced own-coin return did not restore the coin count')
    check(mem[body_addr(0) + sym['BF']] & sym['F_ON'],
          'forced own-coin return did not put the coin back on the board')

    # Queen target becomes legal from history when no Due blocks it.
    fresh_board()
    mem[sym['had']] = 1
    check(queen_is_targeted(), 'Queen was not targeted after qualifying history')

    # No history means no Queen target.
    fresh_board()
    check(not queen_is_targeted(), 'Queen target appeared without any colour history')

    # Returning/owing state without a new pocket must not fabricate history.
    fresh_board()
    mem[sym['dues']] = 1
    check(run_to(sym['ph_resolve'], sym['stats_stroke']), 'no-pocket Due resolve did not reach accounting')
    check(mem[sym['had']] == 0 and mem[sym['had'] + 1] == 0,
          'return/owe processing fabricated colour history')

    # A pending Due remains a Queen blocker even when history exists.
    fresh_board()
    mem[sym['had']] = 1
    mem[sym['dues']] = 1
    check(not queen_is_targeted(), 'pending Due did not block Queen targeting')

    print('queen-history assembled checks: PASS')


if __name__ == '__main__':
    main()
