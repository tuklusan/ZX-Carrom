#!/usr/bin/env python3
"""Focused assembled checks for ICF 137 pass-streak board replay."""
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
        'PASS_REPLAY_LIMIT', 'PH_NEWBOARD', 'PH_THINK0', 'pass_turn',
        'record_progress', 'pass_streak', 'new_match', 'setup_board',
        'ph_resolve', 'msg_show', 'break_made', 'seat', 'white_pair',
        'pk_count', 'pk_ids', 'BODIES', 'BSZ', 'BF',
    )
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('missing symbols: ' + ', '.join(missing))
    if sym['PASS_REPLAY_LIMIT'] != 12:
        raise SystemExit('pass-replay check failed: doubles threshold is not 12')

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
            raise SystemExit('pass-replay check failed: ' + message)

    def call_routine(addr, max_tstates=500000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == sentinel

    def run_to(addr, stop, max_tstates=2000000):
        tracer.run(addr, stop, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == stop

    def carry():
        return bool(regs[F] & 1)

    def board_ready():
        check(call_routine(sym['new_match']), 'new_match did not return')
        check(call_routine(sym['setup_board']), 'setup_board did not return')
        mem[sym['phase']] = sym['PH_THINK0']
        mem[sym['seat']] = 0

    # Eleven passes are not enough; the twelfth schedules exactly one replay.
    board_ready()
    for n in range(11):
        check(call_routine(sym['pass_turn']) and not carry(),
              f'pass {n + 1} triggered replay too early')
    check(mem[sym['pass_streak']] == 11, 'streak did not reach 11')
    check(mem[sym['phase']] == sym['PH_THINK0'], 'phase changed before the threshold')
    check(call_routine(sym['pass_turn']) and carry(), 'twelfth pass did not signal replay')
    check(mem[sym['pass_streak']] == 0, 'threshold replay did not clear the streak')
    check(mem[sym['phase']] == sym['PH_NEWBOARD'], 'threshold did not schedule board replay')

    # A replay event is one-shot: the next pass starts a new streak.
    mem[sym['phase']] = sym['PH_THINK0']
    check(call_routine(sym['pass_turn']) and not carry(), 'post-replay first pass retriggered replay')
    check(mem[sym['pass_streak']] == 1, 'post-replay streak did not restart at one')

    # A qualifying progress event clears a prior pass sequence.
    mem[sym['pass_streak']] = 5
    check(call_routine(sym['record_progress']), 'progress reset did not return')
    check(mem[sym['pass_streak']] == 0, 'progress did not clear the pass streak')

    # One pass, progress, then eleven passes must still be below threshold.
    check(call_routine(sym['pass_turn']) and not carry(), 'single pass unexpectedly replayed')
    check(call_routine(sym['record_progress']), 'progress after one pass did not return')
    for n in range(11):
        check(call_routine(sym['pass_turn']) and not carry(),
              f'pass after reset {n + 1} triggered replay too early')
    check(mem[sym['pass_streak']] == 11, 'stale pre-progress pass survived reset')
    check(call_routine(sym['pass_turn']) and carry(), 'fresh twelfth pass did not replay')

    # An ordinary own-coin continuation is progress, not a pass.
    board_ready()
    mem[sym['pass_streak']] = 7
    mem[sym['break_made']] = 1
    mem[sym['seat']] = 0
    mem[sym['white_pair']] = 0
    mem[sym['pk_count']] = 1
    mem[sym['pk_ids']] = 0
    mem[sym['BODIES'] + sym['BF']] = 0
    check(run_to(sym['ph_resolve'], sym['msg_show']), 'continuation resolve did not reach message output')
    check(mem[sym['pass_streak']] == 0, 'own-coin continuation incremented or preserved pass streak')
    check(mem[sym['seat']] == 0, 'own-coin continuation advanced the physical seat')
    check(mem[sym['phase']] != sym['PH_NEWBOARD'], 'continuation incorrectly scheduled replay')

    # Fresh match and board setup both clear stale pass state.
    mem[sym['pass_streak']] = 9
    check(call_routine(sym['new_match']), 'restart path did not return')
    check(mem[sym['pass_streak']] == 0, 'restart path left stale pass state')
    mem[sym['pass_streak']] = 9
    check(call_routine(sym['setup_board']), 'new-board setup did not return')
    check(mem[sym['pass_streak']] == 0, 'new-board setup left stale pass state')

    print('pass-replay assembled checks: PASS')


if __name__ == '__main__':
    main()
