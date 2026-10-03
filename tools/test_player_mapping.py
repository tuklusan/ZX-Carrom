#!/usr/bin/env python3
"""Focused assembled checks for logical-player identity and physical-seat rotation."""
import argparse

from skoolkit import CSimulator
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, A, F, H, L, SP, PC
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
        'new_match', 'setup_board', 'reset_player_map', 'logical_for_seat',
        'mover_pair', 'seat_for_player', 'validate_player_map',
        'rotate_players_right', 'msg_profile', 'msg_s', 'PROFNAMES',
        'PROFILES', 'ai_begin', 'pf', 'seat', 'player_at_seat',
        'boards_in_game', 'games_played', 'break_off', 'white_pair',
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

    def fail(message):
        raise SystemExit('player-map check failed: ' + message)

    def check(condition, message):
        if not condition:
            fail(message)

    def call_routine(addr, max_ops=500000):
        sentinel = 0x7EFE
        sp = (regs[SP] - 2) & 0xFFFF
        mem[sp] = sentinel & 255
        mem[(sp + 1) & 0xFFFF] = sentinel >> 8
        regs[SP] = sp
        tracer.run(addr, sentinel, 0, max_ops, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == sentinel

    def run_to(addr, stop, max_ops=50000):
        tracer.run(addr, stop, 0, max_ops, False,
                   None, None, None, None, '$', '02X', '04X')
        return regs[PC] == stop

    def carry():
        return bool(regs[F] & 1)

    def mapping():
        base = sym['player_at_seat']
        return list(mem[base:base + 4])

    def set_mapping(values):
        base = sym['player_at_seat']
        mem[base:base + 4] = values

    def reverse_lookup(player, max_ops=500):
        regs[A] = player
        returned = call_routine(sym['seat_for_player'], max_ops)
        return returned, regs[A], carry()

    def profile_name_pointer(player):
        base = sym['PROFNAMES'] + 2 * player
        return mem[base] | (mem[base + 1] << 8)

    def planner_profile(player):
        base = sym['PROFILES'] + 8 * player
        return bytes(mem[base:base + 8])

    def profile_probe(physical_seat, logical_player):
        mem[sym['seat']] = physical_seat
        for i in range(8):
            mem[sym['pf'] + i] = 0xCC
        start = sym['ai_begin']
        stop = None
        for pos in range(start, start + 40):
            if mem[pos] == 0xED and mem[pos + 1] == 0xB0:  # LDIR
                stop = pos + 2
                break
        check(stop is not None, 'planner profile copy has no LDIR nearby')
        check(run_to(start, stop), 'planner profile copy did not reach its stop point')
        check(bytes(mem[sym['pf']:sym['pf'] + 8]) == planner_profile(logical_player),
              f'planner profile changed with physical seat {physical_seat}')

        check(run_to(sym['msg_profile'], sym['msg_s']),
              'profile-name resolver did not reach message output')
        resolved = (regs[H] << 8) | regs[L]
        check(resolved == profile_name_pointer(logical_player),
              f'profile name changed with physical seat {physical_seat}')

    # Fresh-match initialization must erase any damaged mapping.
    set_mapping([3, 3, 3, 3])
    check(call_routine(sym['new_match']), 'new_match did not return')
    check(mapping() == [0, 1, 2, 3], 'fresh match is not one-to-one identity')
    check(call_routine(sym['validate_player_map']) and not carry(),
          'fresh identity map was rejected')
    for player in range(4):
        returned, seat, bad = reverse_lookup(player)
        check(returned and not bad and seat == player,
              f'fresh reverse lookup failed for player {player}')

    # First required side change: every player moves one chair clockwise.
    check(call_routine(sym['rotate_players_right']) and not carry(),
          'first valid side change was rejected')
    check(mapping() == [3, 0, 1, 2], 'first side change mapping is wrong')
    for physical_seat, logical_player in enumerate(mapping()):
        profile_probe(physical_seat, logical_player)

    # Forced seat swap: logical identity must still own both profile selectors.
    set_mapping([1, 0, 2, 3])
    profile_probe(1, 0)
    profile_probe(0, 1)

    # Two valid transitions must stay a complete permutation.
    set_mapping([0, 1, 2, 3])
    check(call_routine(sym['rotate_players_right']) and not carry(),
          'valid transition one was rejected')
    check(call_routine(sym['rotate_players_right']) and not carry(),
          'valid transition two was rejected')
    check(mapping() == [2, 3, 0, 1], 'second side change mapping is wrong')
    check(call_routine(sym['validate_player_map']) and not carry(),
          'second side change lost a logical player')

    # On that second mapping, logical player 2 is the breaker for game index 2.
    mem[sym['boards_in_game']] = 0
    mem[sym['games_played']] = 2
    mem[sym['break_off']] = 0
    check(call_routine(sym['setup_board']), 'setup_board did not return')
    check(mem[sym['seat']] == 0, 'breaker was derived from profile/seat instead of mapping')
    check(mem[sym['white_pair']] == 0, 'breaker colour pair is not logical player 2 pair')

    # Controlled bad fixtures: duplicate/missing and stray logical ids are rejected.
    set_mapping([0, 0, 2, 3])
    check(call_routine(sym['validate_player_map']) and carry(),
          'duplicate/missing map was accepted')
    returned, seat, bad = reverse_lookup(1, 1000)
    check(returned and bad and seat == 0xFF,
          'missing logical player did not take the bounded failure path')
    check(call_routine(sym['rotate_players_right']) and carry(),
          'transition did not signal rejection of duplicate/missing map')
    check(mapping() == [3, 0, 1, 2],
          'rejected map was not recovered to a valid rotated identity')

    set_mapping([0, 1, 2, 9])
    check(call_routine(sym['validate_player_map']) and carry(),
          'out-of-range/missing map was accepted')

    print('player-map assembled checks: PASS')


if __name__ == '__main__':
    main()
