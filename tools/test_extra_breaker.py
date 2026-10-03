#!/usr/bin/env python3
"""Focused assembled checks for the tied eighth-board fresh breaker toss."""
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
        'new_match', 'setup_board', 'ph_afterboard', 'PH_NEWBOARD', 'phase',
        'extra_board', 'extra_breaker', 'player_at_seat', 'seat', 'white_pair',
        'boards_in_game', 'games_played', 'break_off', 'game_score',
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
            raise SystemExit('extra-breaker check failed: ' + message)

    def call_routine(addr, max_tstates=1000000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == sentinel

    def set_mapping(values):
        base = sym['player_at_seat']
        mem[base:base + 4] = values

    def seat_for_player(player):
        mapping = list(mem[sym['player_at_seat']:sym['player_at_seat'] + 4])
        return mapping.index(player)

    check(call_routine(sym['new_match']), 'new_match did not return')
    mapping = [2, 3, 0, 1]
    set_mapping(mapping)

    # Inject each possible fresh toss. The logical player and mapped physical seat must win.
    for toss in range(4):
        mem[sym['extra_board']] = 1
        mem[sym['extra_breaker']] = toss
        mem[sym['boards_in_game']] = 8
        mem[sym['games_played']] = 1
        mem[sym['break_off']] = 3  # ordinary formula deliberately disagrees for most tosses
        check(call_routine(sym['setup_board']), f'setup did not return for toss {toss}')
        check(mem[sym['seat']] == seat_for_player(toss),
              f'toss {toss} did not select its mapped physical seat')
        check(mem[sym['white_pair']] == (toss & 1),
              f'toss {toss} did not select its logical white pair')
        check(mem[sym['extra_board']] == 0, 'extra-board state was not consumed')

    # Normal boards ignore stale extra_breaker data and keep ordinary rotation.
    set_mapping(mapping)
    mem[sym['extra_board']] = 0
    mem[sym['extra_breaker']] = 3
    mem[sym['boards_in_game']] = 2
    mem[sym['games_played']] = 1
    mem[sym['break_off']] = 0
    expected = (2 + 1 + 0) & 3
    check(call_routine(sym['setup_board']), 'normal setup did not return')
    check(mem[sym['seat']] == seat_for_player(expected), 'normal board used stale extra toss')
    check(mem[sym['white_pair']] == (expected & 1), 'normal board white pair changed')
    check(mem[sym['extra_breaker']] == 3, 'normal board consumed stale toss payload')

    # A tied eighth board must schedule a new board and arm a fresh 0..3 breaker selection.
    mem[sym['boards_in_game']] = 8
    mem[sym['game_score']] = 17
    mem[sym['game_score'] + 1] = 17
    mem[sym['extra_board']] = 0
    mem[sym['extra_breaker']] = 0xFF
    check(call_routine(sym['ph_afterboard']), 'tied eighth-board transition did not return')
    check(mem[sym['phase']] == sym['PH_NEWBOARD'], 'tied eighth board did not schedule another board')
    check(mem[sym['extra_board']] == 1, 'tied eighth board did not arm extra-board state')
    check(mem[sym['extra_breaker']] < 4, 'fresh extra-board toss is outside 0..3')

    print('extra-breaker assembled checks: PASS')


if __name__ == '__main__':
    main()
