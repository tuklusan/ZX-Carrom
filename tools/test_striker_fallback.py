#!/usr/bin/env python3
"""Focused assembled checks for legal striker fallback placement."""
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
        'new_match', 'setup_board', 'fallback_legal', 'plan_fallback',
        'strike_legal', 'plan_u', 'plan_speed', 'plan_vx', 'plan_vy',
        'ai_on', 'ai_u', 'ai_v', 'ai_col', 'seat', 'phase',
        'pass_streak', 'PH_WAIT', 'PH_NEWBOARD',
    )
    missing = [name for name in required if name not in sym]
    if missing:
        raise SystemExit('striker-fallback check missing symbols: ' + ', '.join(missing))

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
            raise SystemExit('striker-fallback check failed: ' + message)

    def call_routine(addr, aval=None, max_tstates=1500000):
        if aval is not None:
            regs[A] = aval & 255
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_tstates, False,
                   None, None, None, None, '$', '02X', '04X')
        check(regs[PC] == sentinel, 'routine did not return')
        return bool(regs[F] & 1)

    def fresh():
        regs[SP] = base_sp
        call_routine(sym['new_match'])
        call_routine(sym['setup_board'])
        mem[sym['seat']] = 0
        mem[sym['pass_streak']] = 0
        mem[sym['ai_col']] = 0
        mem[sym['ai_on']:sym['ai_on'] + 20] = [0] * 20
        mem[sym['ai_u']:sym['ai_u'] + 20] = [0] * 20
        mem[sym['ai_v']:sym['ai_v'] + 20] = [0] * 20

    def block(piece, u, v=-33):
        mem[sym['ai_on'] + piece] = 1
        mem[sym['ai_u'] + piece] = u & 255
        mem[sym['ai_v'] + piece] = v & 255

    def half_from_plan():
        v = mem[sym['plan_u']]
        if v >= 128:
            v -= 256
        check(v % 2 == 0, 'plan_u is not a half-pixel baseline multiple')
        return v // 2

    def legal(u):
        return not call_routine(sym['strike_legal'], u)

    # The old centre is blocked; the deterministic scan must choose another legal point.
    fresh()
    block(0, 0)
    check(not call_routine(sym['fallback_legal']), 'fallback scan rejected an available baseline')
    u = half_from_plan()
    check(u != 0 and legal(u), 'blocked centre was selected or replacement is illegal')

    # Make every negative point illegal while leaving centre legal.
    fresh()
    for piece, u in enumerate((-26, -21, -16, -11, -6, -3)):
        block(piece, u, -29)
    check(not call_routine(sym['fallback_legal']), 'centre-only setup found no placement')
    check(half_from_plan() == 0 and legal(0), 'legal centre was not accepted')

    # Ordinary targetable fallback still commits a finite legal stroke.
    fresh()
    block(0, 0, 0)
    check(not call_routine(sym['plan_fallback']), 'targetable fallback reported no placement')
    u = half_from_plan()
    check(legal(u), 'targetable fallback selected an illegal striker position')
    check(mem[sym['plan_speed']] or mem[sym['plan_speed'] + 1],
          'targetable fallback committed zero speed')
    vx = mem[sym['plan_vx']] | (mem[sym['plan_vx'] + 1] << 8)
    vy = mem[sym['plan_vy']] | (mem[sym['plan_vy'] + 1] << 8)
    check(vx or vy, 'targetable fallback committed zero velocity')

    # Cover the full -28..28 baseline. No shot may be committed; the turn passes.
    fresh()
    for piece, u in enumerate((-24, -15, -6, 3, 12, 21, 27)):
        block(piece, u)
    mem[sym['plan_u']] = 77
    mem[sym['plan_vx']] = 0x34
    mem[sym['plan_vx'] + 1] = 0x12
    mem[sym['plan_vy']] = 0x78
    mem[sym['plan_vy'] + 1] = 0x56
    check(call_routine(sym['plan_fallback']), 'fully blocked baseline did not take pass path')
    check(mem[sym['plan_u']] == 77, 'no-placement path committed a striker position')
    check((mem[sym['plan_vx']] | (mem[sym['plan_vx'] + 1] << 8)) == 0x1234,
          'no-placement path changed X velocity')
    check((mem[sym['plan_vy']] | (mem[sym['plan_vy'] + 1] << 8)) == 0x5678,
          'no-placement path changed Y velocity')
    check(mem[sym['phase']] in (sym['PH_WAIT'], sym['PH_NEWBOARD']),
          'no-placement path did not schedule a pass/replay')

    # Controlled old behaviour: replace the scanner with the former unchecked centre choice.
    fresh()
    block(0, 0)
    p = sym['fallback_legal']
    saved = list(mem[p:p + 7])
    bad = [0xAF, 0x32, sym['plan_u'] & 255, sym['plan_u'] >> 8, 0xB7, 0xC9, 0x00]
    mem[p:p + 7] = bad
    check(not call_routine(sym['plan_fallback']), 'controlled old fixture did not commit')
    check(half_from_plan() == 0 and not legal(0),
          'controlled old fixture did not reproduce illegal centre placement')
    mem[p:p + 7] = saved

    print('striker-fallback assembled checks: PASS')


if __name__ == '__main__':
    main()
