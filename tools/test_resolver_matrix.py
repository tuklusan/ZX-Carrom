#!/usr/bin/env python3
"""Assembled Phase-2 resolver matrix for striker, Due, Queen, returns, and PTS."""
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
        'new_match', 'setup_board', 'ph_resolve', 'stats_stroke',
        'break_made', 'seat', 'white_pair', 'pk_count', 'pk_ids',
        'left', 'dues', 'score', 'rret', 'rcont', 'qstate',
        'BODIES', 'BSZ', 'BF', 'BX', 'BY', 'F_ON', 'QUEEN', 'STRIKER',
    )
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('resolver-matrix check missing symbols: ' + ', '.join(missing))

    snap = Snapshot.get(args.snap)
    sim = from_snapshot(CSimulator, snap, {}, {'ay': [None] * 16},
                        {'fast_djnz': False, 'fast_ldir': False})
    tracer = Tracer(sim, snap.border, 0, 0, list(snap.ay), snap.outfe, False)
    sim.set_tracer(tracer)
    mem = sim.memory
    regs = sim.registers
    base_sp = regs[SP]

    def check(condition, message):
        if not condition:
            raise SystemExit('resolver-matrix check failed: ' + message)

    def call_routine(addr, max_tstates=1000000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        check(regs[PC] == sentinel, 'routine did not return')
        return bool(regs[F] & 1)

    def run_to(addr, stop, max_tstates=2500000):
        tracer.run(addr, stop, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        check(regs[PC] == stop, 'resolver did not reach accounting')

    def body_addr(piece):
        return sym['BODIES'] + piece * sym['BSZ']

    def on_board(piece):
        return bool(mem[body_addr(piece) + sym['BF']] & sym['F_ON'])

    def set_points(p0, p1):
        mem[sym['score']] = p0 % 100
        mem[sym['score'] + 1] = p1 % 100
        mem[sym['score'] + 2] = p0 // 100
        mem[sym['score'] + 3] = p1 // 100

    def points(pair):
        return mem[sym['score'] + pair] + 100 * mem[sym['score'] + 2 + pair]

    def fresh():
        regs[SP] = base_sp
        check(not call_routine(sym['new_match']), 'new_match returned carry')
        check(not call_routine(sym['setup_board']), 'setup_board returned carry')
        mem[sym['break_made']] = 1
        mem[sym['seat']] = 0
        mem[sym['white_pair']] = 0
        mem[sym['left']] = 9
        mem[sym['left'] + 1] = 9
        mem[sym['dues']] = 0
        mem[sym['dues'] + 1] = 0
        mem[sym['qstate']] = 0
        mem[sym['rret']] = 0
        mem[sym['rret'] + 1] = 0
        set_points(0, 0)

    def mark_spares(ids):
        for piece in ids:
            mem[body_addr(piece) + sym['BF']] = 0
        mem[sym['left']] = 9 - len(ids)

    def pocket(ids):
        mem[sym['pk_count']] = len(ids)
        for i, piece in enumerate(ids):
            mem[sym['pk_ids'] + i] = piece
            mem[body_addr(piece) + sym['BF']] = 0

    def score_now():
        check(not call_routine(sym['stats_stroke']), 'accounting signalled overflow')

    def invariants(tag):
        l0, l1 = mem[sym['left']], mem[sym['left'] + 1]
        check(0 <= l0 <= 9 and 0 <= l1 <= 9, tag + ': left count outside 0..9')
        seen = set()
        for piece in range(19):
            if not on_board(piece):
                continue
            b = body_addr(piece)
            xy = (mem[b + sym['BX'] + 1], mem[b + sym['BY'] + 1])
            check(xy not in seen, tag + ': duplicate on-board coin centre')
            seen.add(xy)

    def proper_case(tag, own, opp, existing_due):
        fresh()
        due_total = existing_due + 1
        spares = list(range(due_total))
        mark_spares(spares)
        set_points(due_total, 0)
        mem[sym['dues']] = existing_due
        current_own = due_total
        ids = []
        if own:
            ids.append(current_own)
        if opp:
            ids.append(9)
        ids.append(sym['STRIKER'])
        pocket(ids)
        run_to(sym['ph_resolve'], sym['stats_stroke'])

        expected_returns = due_total + (1 if own else 0)
        check(mem[sym['dues']] == 0, tag + ': mover Due did not recover')
        check(mem[sym['dues'] + 1] == 0, tag + ': opponent Due changed')
        check(mem[sym['left']] == 9, tag + ': mover left count is wrong')
        check(mem[sym['rret']] == expected_returns, tag + ': mover return count is wrong')
        check(mem[sym['rret'] + 1] == 0, tag + ': opponent return was fabricated')
        for piece in spares:
            check(on_board(piece), tag + ': Due body was not returned')
        if own:
            check(on_board(current_own), tag + ': stroke own coin was not returned')
        if opp:
            check(not on_board(9) and mem[sym['left'] + 1] == 8,
                  tag + ': opponent coin did not remain pocketed')
        else:
            check(mem[sym['left'] + 1] == 9, tag + ': opponent left count changed')
        check(mem[sym['rcont']] == (1 if own else 0),
              tag + ': continuation state violates striker guardrail')
        score_now()
        check((points(0), points(1)) == (0, 1 if opp else 0),
              tag + ': PTS disagrees with retained/returned colours')
        invariants(tag)

    for due in (0, 1):
        proper_case('striker-alone-due' + str(due), False, False, due)
        proper_case('striker-own-due' + str(due), True, False, due)
        proper_case('striker-opp-due' + str(due), False, True, due)
        proper_case('striker-both-due' + str(due), True, True, due)

    # No available mover coin: the new Due must remain outstanding.
    fresh()
    pocket([sym['STRIKER']])
    run_to(sym['ph_resolve'], sym['stats_stroke'])
    check(mem[sym['dues']] == 1 and mem[sym['rret']] == 0,
          'striker-alone suppressed an unavailable Due')
    check(mem[sym['rcont']] == 0, 'striker-alone continued')
    invariants('striker-alone-unavailable')

    # Own coin returns, but with no spare body the separate Due remains.
    fresh()
    pocket([0, sym['STRIKER']])
    run_to(sym['ph_resolve'], sym['stats_stroke'])
    check(mem[sym['dues']] == 1 and mem[sym['rret']] == 1,
          'striker+own suppressed or falsely paid its Due')
    check(on_board(0) and mem[sym['left']] == 9,
          'striker+own did not return the stroke coin')
    check(mem[sym['rcont']] == 1, 'striker+own incorrectly ended the turn')
    score_now()
    check(points(0) == 0, 'returned own coin remained counted in PTS')
    invariants('striker-own-unavailable')

    # Combined Queen + striker + both colours + existing mover Due.
    fresh()
    spares = [0, 1]
    mark_spares(spares)
    set_points(2, 0)
    mem[sym['dues']] = 1
    pocket([sym['QUEEN'], 2, 9, sym['STRIKER']])
    run_to(sym['ph_resolve'], sym['stats_stroke'])
    check(mem[sym['qstate']] == 0 and on_board(sym['QUEEN']),
          'combined case did not physically return the Queen')
    check(mem[sym['dues']] == 0 and mem[sym['rret']] == 3,
          'combined case did not resolve forced returns plus existing/new Due')
    check(mem[sym['left']] == 9 and mem[sym['left'] + 1] == 8,
          'combined case left counts are wrong')
    check(all(on_board(x) for x in (0, 1, 2)),
          'combined case returned a wrong mover-colour body')
    check(not on_board(9), 'combined case returned the opponent coin without its own obligation')
    check(mem[sym['rcont']] == 1, 'combined Queen+own+striker case did not continue')
    score_now()
    check((points(0), points(1)) == (0, 1),
          'combined case PTS disagrees with final physical state')
    invariants('combined-queen-striker-both-existing-due')

    print('resolver-matrix assembled checks: PASS')


if __name__ == '__main__':
    main()
