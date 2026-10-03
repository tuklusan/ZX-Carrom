#!/usr/bin/env python3
"""Headless test harness: runs the loaded snapshot in SkoolKit's Z80 simulator,
logs every status-line message with its time, and can dump screenshots."""
import sys, os, argparse
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, T, F, SP, PC
from skoolkit import CSimulator
from skoolkit.trace import Tracer
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sym = {}
for ln in open(os.path.join(HERE, 'carrom.sym')):
    p = ln.replace(':', '').split()
    if len(p) >= 3 and p[1].upper() == 'EQU':
        v = p[2]
        if v.lower().startswith('0x'):
            sym[p[0]] = int(v, 16)
        elif v.upper().endswith('H'):
            sym[p[0]] = int(v[:-1], 16)
        else:
            sym[p[0]] = int(v, 0)
PAL = [(0, 0, 0), (0, 0, 0xD7), (0xD7, 0, 0), (0xD7, 0, 0xD7), (0, 0xD7, 0), (0, 0xD7, 0xD7), (0xD7, 0xD7, 0), (0xD7, 0xD7, 0xD7),
       (0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF), (0, 0xFF, 0), (0, 0xFF, 0xFF), (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)]

def screenshot(mem, path, scale=2):
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for y in range(192):
        base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for xb in range(32):
            b = mem[base + xb]
            a = mem[0x5800 + (y // 8) * 32 + xb]
            br = 8 if a & 64 else 0
            ink = PAL[(a & 7) + br]; paper = PAL[((a >> 3) & 7) + br]
            for k in range(8):
                px[xb * 8 + k, y] = ink if b & (128 >> k) else paper
    im.resize((256 * scale, 192 * scale), Image.NEAREST).save(path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--snap', default=os.path.join(HERE, 'loaded.z80'))
    ap.add_argument('--secs', type=float, default=60)
    ap.add_argument('--shots', default='')        # comma list of seconds for screenshots
    ap.add_argument('--prefix', default='test/s')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--seed', type=int, default=None)
    ap.add_argument('--nogroove', action='store_true')
    ap.add_argument('--accept', action='store_true')
    ap.add_argument('--quit-check', action='store_true')
    a = ap.parse_args()
    snap = Snapshot.get(a.snap)
    sim = from_snapshot(CSimulator, snap, {}, {'ay': [None] * 16}, {'fast_djnz': False, 'fast_ldir': False})
    tracer = Tracer(sim, snap.border, 0, 0, list(snap.ay), snap.outfe, False)
    sim.set_tracer(tracer)
    mem = sim.memory
    if a.seed is not None:   # FRAMES, used for the seed
        mem[23672] = a.seed & 255; mem[23673] = (a.seed >> 8) & 255
    regs = sim.registers
    t0 = regs[T]
    end = t0 + int(a.secs * 3500000)
    shots = sorted(float(s) for s in a.shots.split(',') if s)
    stop = sym['msg_show']
    pc = snap.pc
    msgs = []
    seats_seen = set()
    modes_seen = set()
    fast_seen = set()
    phases_seen = set()
    song_positions = set()
    song_prev = None
    song_wraps = 0
    pause_ref = None
    pause_frozen = True
    pause_resumed = False
    restart_seen = False
    points_seen = [set(), set()]
    loading_band_clean = (
        all((mem[0x5800+r*32+x] & 0x38) == 0x08
            for r in range(3) for x in range(32))
        and all((mem[0x5800+r*32+x] & 0x38) != 0x08
                for r in range(3,24) for x in range(32))
    )
    loading_board_uniform = all(mem[0x5800+r*32+x] == 0x45
                                for r in range(6,17) for x in range(9,23))
    def paddr0(xb,y):
        return 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | xb
    intro_border_ref = bytes(mem[paddr0(xb,y)]
                             for y in range(136,144)
                             for xb in list(range(0,12))+list(range(20,32)))
    intro_prompt = False
    intro_border_clean = True
    ribbon_intro = False
    ribbon_game = False
    star_prev = [None, None, None]
    star_changes = [0, 0, 0]
    protected_ref = None
    protected_clean = False
    east_margin_clean = True
    east_base_clean = True
    east_attr_clean = True
    small_game_title = False
    title_baseline = False
    star_sparse = False
    play_msgs = 0
    strikes = 0
    stray_total = 0
    if a.quit_check and (mem[0x7F00] != 0x31 or mem[0x7F03] != 0xC9):
        raise SystemExit('quit return trampoline is not installed')
    def draw(scr, frame, border, kb):
        nonlocal song_prev, song_wraps, pause_ref, pause_frozen, pause_resumed, restart_seen
        nonlocal intro_prompt, intro_border_clean, ribbon_intro, ribbon_game, protected_ref, protected_clean
        nonlocal east_margin_clean, east_base_clean, east_attr_clean, small_game_title, title_baseline, star_sparse
        now_s = (regs[T] - t0) / 3500000
        for i in range(8): kb[i] = 0
        if a.nogroove: mem[sym['gm_run']] = 0

        def paddr(xb,y):
            return 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | xb

        if 0.4 <= now_s < 1.4:
            aa=[mem[0x5800+17*32+c] for c in range(12,19)]
            if aa and all(v & 0x80 for v in aa):
                intro_prompt = True
            live = bytes(mem[paddr(xb,y)]
                         for y in range(136,144)
                         for xb in list(range(0,12))+list(range(20,32)))
            if live != intro_border_ref:
                intro_border_clean = False
            cols=[mem[0x5800+(10+i)*32+31] & 7 for i in range(4)]
            if cols == [2,6,4,5]:
                ribbon_intro = True
        if 2.0 <= now_s < 5.0:
            vals=[mem[sym['star_far']], mem[sym['star_mid']], mem[sym['star_near']]]
            for i,v in enumerate(vals):
                if star_prev[i] is not None and v != star_prev[i]:
                    star_changes[i] += 1
                star_prev[i] = v
            cols=[mem[0x5800+(10+i)*32+31] & 7 for i in range(4)]
            if cols == [2,6,4,5]:
                ribbon_game = True
            inside=False
            outside=False
            for yy in range(8):
                for xx in range(256):
                    val=mem[paddr(xx//8,yy)]
                    if val & (128 >> (xx & 7)):
                        if 58 <= xx < 198:
                            inside=True
                        else:
                            outside=True
            if inside and not outside:
                small_game_title = True
            title = "SANYALnet Labs  Carrom Arena"
            aligned = True
            for i,ch in enumerate(title):
                if ch == ' ':
                    continue
                rows = []
                for yy in range(8):
                    for xx in range(5):
                        px = 58 + i*5 + xx
                        val = mem[paddr(px//8,yy)]
                        if val & (128 >> (px & 7)):
                            rows.append(yy)
                if not rows or max(rows) != 6:
                    aligned = False
                    break
            if aligned:
                title_baseline = True
            dots = 0
            for yy in range(24,168):
                for xx in list(range(0,24))+list(range(224,248)):
                    val = mem[paddr(xx//8,yy)]
                    if val & (128 >> (xx & 7)):
                        dots += 1
            if 8 <= dots <= 36:
                star_sparse = True

        if 2.2 <= now_s < 2.3 and protected_ref is None:
            keep=[]
            for y in list(range(8,24))+list(range(168,184)):
                keep.extend(mem[paddr(xb,y)] for xb in list(range(0,6))+list(range(26,32)))
            keep.extend(mem[paddr(31,y)] for y in range(80,112))
            protected_ref=bytes(keep)
        if 3.2 <= now_s < 3.3 and protected_ref is not None:
            keep=[]
            for y in list(range(8,24))+list(range(168,184)):
                keep.extend(mem[paddr(xb,y)] for xb in list(range(0,6))+list(range(26,32)))
            keep.extend(mem[paddr(31,y)] for y in range(80,112))
            protected_clean = bytes(keep) == protected_ref
        if 2.0 <= now_s < 5.0:
            off=sym['BGBUF']-0x4000
            for yy in range(24,168):
                for xb in (27,31):
                    aa=paddr(xb,yy)
                    if mem[aa] != mem[aa+off]:
                        east_margin_clean = False
                for xb in range(27,32):
                    aa=paddr(xb,yy)+off
                    expected=0xF0 if xb == 31 and 80 <= yy < 112 else 0
                    if mem[aa] != expected:
                        east_base_clean = False
            ribbon_attrs=(0x42,0x46,0x44,0x45)
            for ar in range(3,21):
                for xb in range(28,32):
                    expected=0x47
                    if xb == 31 and 10 <= ar < 14:
                        expected=ribbon_attrs[ar-10]
                    if mem[0x5800+ar*32+xb] != expected:
                        east_attr_clean = False
        if os.environ.get('HUDTEST') and now_s > 3:
            mem[sym['score']] = 25; mem[sym['score']+1] = 7
            mem[sym['score']+2] = 1; mem[sym['score']+3] = 0
            mem[sym['boards_won']] = 12; mem[sym['boards_won']+1] = 3
            mem[sym['games_won']] = 10; mem[sym['games_won']+1] = 1; mem[sym['dues']] = 1
        if os.environ.get('QUITTEST') and 8.0 <= now_s < 8.2: kb[2] |= 1      # Q
        if os.environ.get('KEYTEST'):
            if 10.0 <= now_s < 10.2 or 13.0 <= now_s < 13.2: kb[7] |= 4        # M
            if 16.0 <= now_s < 16.2: kb[7] |= 1                             # SPACE
        if a.accept:
            if 8.0 <= now_s < 8.2 or 9.5 <= now_s < 9.7 or 11.0 <= now_s < 11.2: kb[7] |= 4
            if 13.0 <= now_s < 13.2 or 15.0 <= now_s < 15.2: kb[7] |= 1
            if 17.0 <= now_s < 17.2 or 18.0 <= now_s < 18.2: kb[1] |= 8
            if 125.0 <= now_s < 125.2: kb[2] |= 8
        if 1.5 <= now_s < 1.7:
            kb[6] |= 1                       # ENTER: leave the title page
        if a.accept:
            modes_seen.add(mem[sym['snd_mode']])
            fast_seen.add(mem[sym['fast']])
            phases_seen.add(mem[sym['phase']])
            if mem[sym['gm_run']] and not mem[sym['music_off']] and not mem[sym['paused']]:
                p = mem[sym['gm_songp']] | (mem[sym['gm_songp'] + 1] << 8)
                song_positions.add(p)
                if song_prev is not None and p < song_prev and now_s < 124.0:
                    song_wraps += 1
                song_prev = p
            state = (mem[sym['phase']], mem[sym['timer']], mem[sym['ticks']] | (mem[sym['ticks'] + 1] << 8), mem[sym['seat']], mem[sym['gm_songp']] | (mem[sym['gm_songp'] + 1] << 8), mem[sym['star_far']], mem[sym['star_mid']], mem[sym['star_near']])
            if mem[sym['paused']] and now_s >= 13.3:
                if pause_ref is None:
                    pause_ref = state
                elif state != pause_ref:
                    pause_frozen = False
            if pause_ref is not None and not mem[sym['paused']] and now_s >= 15.3 and state != pause_ref:
                pause_resumed = True
            points_seen[0].add(mem[sym['score']] + 100 * mem[sym['score'] + 2])
            points_seen[1].add(mem[sym['score'] + 1] + 100 * mem[sym['score'] + 3])
            if 125.2 <= now_s <= 127.0 and mem[sym['phase']] == 8 and mem[sym['timer']] >= 60:
                if not any(mem[sym[k]] for k in ('games_played', 'boards_in_game')) and not any(mem[sym['score'] + i] for i in range(4)) and not any(mem[sym['boards_won'] + i] for i in range(2)) and not any(mem[sym['games_won'] + i] for i in range(2)):
                    restart_seen = True
        return True
    import io, contextlib
    while regs[T] < end:
        nxt = end
        if shots:
            nxt = min(end, t0 + int(shots[0] * 3500000))
        with contextlib.redirect_stdout(io.StringIO()):
            tracer.run(pc, stop, 0, nxt - regs[T], True, draw, None, None, None, '$', '02X', '04X')
        pc = regs[24]
        now = (regs[T] - t0) / 3500000
        if shots and regs[T] >= t0 + int(shots[0] * 3500000):
            screenshot(mem, f"{a.prefix}_{shots[0]:06.1f}.png")
            shots.pop(0)
        if pc == stop:
            text = bytes(mem[sym['msg_buf']:sym['msg_buf'] + 64]).split(b'\0')[0].decode('latin1').rstrip()
            sc = (mem[sym['score']] + 100 * mem[sym['score'] + 2],
                  mem[sym['score'] + 1] + 100 * mem[sym['score'] + 3])
            left = (mem[sym['left']], mem[sym['left'] + 1])
            msgs.append((now, text))
            if 'THINKS' in text or ' BREAK' in text:
                # every play-area pixel outside the pieces must match the clean board copy
                rects=[]
                for i in range(20):
                    b=sym['BODIES']+i*24
                    if mem[b+14]&1:
                        r=mem[b+20]; rects.append((mem[b+1]-r-1, mem[b+3]-r-1, mem[b+1]+r+1, mem[b+3]+r+1))
                    if mem[b+18]:   # still drawn where it was last frame (redrawn on the next render)
                        rects.append((mem[b+16], mem[b+17], mem[b+16]+2*mem[b+20], mem[b+17]+2*mem[b+20]))
                bad=0; strays=[]
                for y in range(16,176):
                    base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
                    for xb in range(6,26):
                        d=mem[base+xb]^mem[base+xb+sym['BGBUF']-0x4000]
                        if d:
                            for k in range(8):
                                if d&(128>>k):
                                    x=xb*8+k
                                    if not any(r[0]<=x<=r[2] and r[1]<=y<=r[3] for r in rects): bad+=1; bx,by=x,y; strays.append((x,y))
                if bad:
                    print(f"   !!! {bad} stray pixels, e.g. ({bx},{by}) at {now:.1f}s")
                    if a.verbose: print("      ", sorted(strays)[:40]); print("       bodies", [(mem[sym['BODIES']+i*24+1],mem[sym['BODIES']+i*24+3],mem[sym['BODIES']+i*24+14]) for i in range(20)])
                bid=mem[sym['ai_bid']]; w=lambda k: (mem[sym[k]]|mem[sym[k]+1]<<8)
                sw=lambda v: v-65536 if v>32767 else v
                sb=lambda v: v-256 if v>127 else v
                info=f"      mode={mem[sym['ai_mode']]} bid={bid} bp={mem[sym['ai_bp']]} su={sb(mem[sym['ai_bsu']])} c64={mem[sym['ai_bc64']]} best={sw(w('ai_best'))} v=({sw(w('plan_vx'))},{sw(w('plan_vy'))}) tn={mem[sym['ai_tn']]}"
                if bid<19:
                    b=sym['BODIES']+bid*24
                    info+=f" coin@({mem[b+1]}.{mem[b]*100//256},{mem[b+3]}.{mem[b+2]*100//256}) seatuv=({sb(mem[sym['ai_u']+bid])},{sb(mem[sym['ai_v']+bid])})"
                info+=f" g=({w('fc_gx')/16:.1f},{w('fc_gy')/16:.1f}) s=({w('fc_sx')/16:.1f},{w('fc_sy')/16:.1f})"
                print(info)
            if a.accept and ('THINKS' in text or ' BREAK' in text):
                seats_seen.add(mem[sym['seat']])
                play_msgs += 1
            if a.accept and 'SHOOTS' in text:
                strikes += 1
            if a.accept:
                stray_total += bad if ('THINKS' in text or ' BREAK' in text) else 0
            if not a.quiet:
                print(f"{now:8.1f}s  [{sc[0]:3d}-{sc[1]:3d}] left W{left[0]} B{left[1]} q{mem[sym['qstate']]}  {text}")
    screenshot(mem, f"{a.prefix}_end.png")
    counter_add = counter_return = counter_reset = True
    if a.accept:
        def call_routine(addr):
            sentinel = 0x7EFE
            sp = (regs[SP] - 2) & 0xFFFF
            mem[sp] = sentinel & 255
            mem[(sp + 1) & 0xFFFF] = sentinel >> 8
            regs[SP] = sp
            tracer.run(addr, sentinel, 0, 50000, False, None, None, None, None, '$', '02X', '04X')
            return regs[PC] == sentinel

        base = sym['score']
        for i in range(8):
            mem[base + i] = 0
        mem[sym['rA']] = 0
        mem[sym['rn']] = 2
        mem[sym['rgiven']] = 0
        counter_add = call_routine(sym['stats_stroke']) and mem[base] == 2 and mem[base + 2] == 0

        mem[sym['rn']] = 0
        mem[sym['rgiven']] = 1
        counter_return = call_routine(sym['stats_stroke']) and mem[base] == 1 and mem[base + 2] == 0

        mem[base] = 99
        mem[base + 2] = 9
        mem[sym['boards_won']] = 4
        mem[sym['games_won']] = 5
        mem[sym['rn']] = 1
        mem[sym['rgiven']] = 0
        overflow_signal = call_routine(sym['stats_stroke']) and bool(regs[F] & 1)
        if overflow_signal:
            overflow_signal = call_routine(sym['stats_clear'])
        counter_reset = overflow_signal and not any(mem[base + i] for i in range(8))

        checks = {
            'four seats': seats_seen == {0, 1, 2, 3},
            'turn flow': play_msgs >= 8 and strikes >= 4,
            'sound cycle': {0, 1, 2}.issubset(modes_seen),
            'speed toggle': {0, 1}.issubset(fast_seen),
            'pause freeze': pause_ref is not None and pause_frozen,
            'pause resume': pause_resumed,
            'restart': restart_seen,
            'live points': any(len(v) > 1 for v in points_seen),
            'points add': counter_add,
            'points return': counter_return,
            'counter reset': counter_reset,
            'groove active': len(song_positions) >= 20,
            'groove loop': song_wraps >= 1,
            'effects idle': mem[sym['sfx_busy']] == 0,
            'phase sane': phases_seen and max(phases_seen) <= 11,
            'screen clean': stray_total == 0,
            'loading band': loading_band_clean,
            'loading board colour': loading_board_uniform,
            'small flashing intro': intro_prompt and intro_border_clean,
            'spectrum ribbon': ribbon_intro and ribbon_game,
            'protected HUD/ribbon': protected_clean and east_margin_clean and east_base_clean and east_attr_clean,
            'small game title': small_game_title and title_baseline,
            'sparse space field': star_sparse,
            'space parallax': star_changes[2] > star_changes[1] > star_changes[0] >= 10,
        }
        for name, ok in checks.items():
            print(f"runtime {name}: {'PASS' if ok else 'FAIL'}")
        bad_checks = [name for name, ok in checks.items() if not ok]
        if bad_checks:
            raise SystemExit('runtime checks failed: ' + ', '.join(bad_checks))
    if a.quit_check:
        ppc = mem[23621] | (mem[23622] << 8)
        subppc = mem[23623]
        report = mem[23610]
        ok = mem[sym['gm_run']] == 0 and report == 8 and ppc == 20 and subppc == 1
        print(f"runtime quit BASIC return: {'PASS' if ok else 'FAIL'} pc={pc} report={report + 1} line={ppc}:{subppc}")
        if not ok:
            raise SystemExit('quit return check failed')
    return msgs

if __name__ == '__main__':
    main()
