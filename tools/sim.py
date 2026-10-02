#!/usr/bin/env python3
"""Headless test harness: runs the loaded snapshot in SkoolKit's Z80 simulator,
logs every status-line message with its time, and can dump screenshots."""
import sys, os, argparse
from skoolkit.snapshot import Snapshot
from skoolkit.simutils import from_snapshot, T
from skoolkit import CSimulator
from skoolkit.trace import Tracer
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sym = {}
for ln in open(os.path.join(HERE, 'carrom.sym')):
    if ': EQU ' in ln:
        k, v = ln.split(': EQU ')
        sym[k.strip()] = int(v.strip(), 16)

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
    def draw(scr, frame, border, kb):
        now_s = (regs[T] - t0) / 3500000
        for i in range(8): kb[i] = 0
        if a.nogroove: mem[sym['gm_run']] = 0
        if os.environ.get('HUDTEST') and now_s > 3:
            mem[sym['score']] = 125; mem[sym['score']+1] = 7; mem[sym['boards_won']] = 12; mem[sym['boards_won']+1] = 3
            mem[sym['games_won']] = 10; mem[sym['games_won']+1] = 1; mem[sym['dues']] = 1
        if os.environ.get('QUITTEST') and 8.0 <= now_s < 8.2: kb[2] |= 1      # Q
        if os.environ.get('KEYTEST'):
            if 10.0 <= now_s < 10.2 or 13.0 <= now_s < 13.2: kb[7] |= 4        # M
            if 16.0 <= now_s < 16.2: kb[7] |= 1                             # SPACE
        if 1.5 <= now_s < 1.7:
            kb[6] |= 1                       # ENTER: leave the title page
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
            sc = (mem[sym['score']], mem[sym['score'] + 1])
            left = (mem[sym['left']], mem[sym['left'] + 1])
            msgs.append((now, text))
            if 'THINKING' in text or 'BREAKS' in text:
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
            if not a.quiet:
                print(f"{now:8.1f}s  [{sc[0]:2d}-{sc[1]:2d}] left W{left[0]} B{left[1]} q{mem[sym['qstate']]}  {text}")
    screenshot(mem, f"{a.prefix}_end.png")
    return msgs

if __name__ == '__main__':
    main()
