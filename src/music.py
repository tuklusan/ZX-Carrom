#!/usr/bin/env python3
"""Generate Carrom Arena beeper music and the long in-game groove.

Blocking title/fanfare music uses a callable adaptation of nanobeep by utz from
ZX-Spectrum-1-Bit-Routines. The live game groove is interrupt-safe and borrows
the same 1-bit phase/noise design so gameplay never stops for background music.
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
NOTES = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11}


def hz(name):
    m = re.match(r'([A-G]#?)(\d)$', name)
    midi = 12 * (int(m.group(2)) + 1) + NOTES[m.group(1)]
    return 440.0 * 2 ** ((midi - 69) / 12)


def nb_inc(name):
    """nanobeep phase increment. Approximate row loop rate is ~2.69 kHz."""
    if name == '.':
        return 0
    n = round(hz(name) * 256.0 / 2692.0)
    return max(1, min(127, n))


def resolve(tokens, prev=0):
    out=[]
    for t in tokens:
        if t == '-':
            out.append(prev)
        elif t == '.':
            prev=0; out.append(0)
        else:
            prev=nb_inc(t); out.append(prev)
    return out, prev


def nb_song(label, speed, bars, loop_bar=None):
    """Generate one 16-row pattern per bar. Drums are ignored by the blocking player."""
    pats=[]; p1=p2=0
    for lead,bass,_drums in bars:
        L=lead.split(); B=bass.split()
        assert len(L)==len(B)==16, (label, lead, bass)
        a,p1=resolve(L,p1); b,p2=resolve(B,p2)
        pats.append(list(zip(a,b)))
    loop_ptr = f'{label}_loopseq' if loop_bar is not None else '0'
    out=[f'{label}:', f'        dw {speed}', f'        dw {loop_ptr}']
    for i in range(len(pats)):
        if loop_bar is not None and i == loop_bar:
            out.append(f'{label}_loopseq:')
        out.append(f'        dw {label}_p{i}-1')
    out.append('        dw 0')
    for i,rows in enumerate(pats):
        out.append(f'{label}_p{i}:')
        for a,b in rows:
            out.append(f'        db {a},{b}')
        out.append('        db 0xFF')
    return out


def bass8(lo, hi):
    return " ".join([lo, '-', hi, '-'] * 4)

# drum patterns
DR_A = "K . H . S . H . K . K . S . H ."
DR_B = "K . . . S . . H K . K . S . T ."
DR_IN = "K . . . . . . . K . . . . . . ."
DR_FILL = "K . S . K . S . S . S . T . T ."

title = []
# intro: drums and bass
for ch in [('A2', 'A3'), ('F2', 'F3'), ('C3', 'C4'), ('G2', 'G3')]:
    title.append((". - - - - - - - - - - - - - - -", bass8(*ch), DR_IN))
# A section (loop point): Am F C G, twice with a variation
A = [
    ("E4 - - - A4 - - - C5 - - - B4 - A4 -", ('A2', 'A3')),
    ("C5 - - - A4 - - - F4 - - - A4 - - -", ('F2', 'F3')),
    ("G4 - - - C5 - - - E5 - - - D5 - C5 -", ('C3', 'C4')),
    ("B4 - - - G4 - - - D4 - - - G4 - - -", ('G2', 'G3')),
    ("E5 - - - D5 - C5 - B4 - - - A4 - - -", ('A2', 'A3')),
    ("C5 - - - A4 - F4 - A4 - C5 - D5 - - -", ('F2', 'F3')),
    ("E5 - - - G4 - - - C5 - E5 - G4 - - -", ('C3', 'C4')),
    ("D5 - - - B4 - G4 - B4 - D5 - . - - -", ('G2', 'G3')),
]
for i, (lead, ch) in enumerate(A):
    title.append((lead, bass8(*ch), DR_FILL if i == 7 else DR_A))
# B section: Dm Am Dm E, Dm Am E Am
B = [
    ("F4 - A4 - D5 - - - C5 - A4 - F4 - - -", ('D3', 'D4')),
    ("E4 - A4 - C5 - - - B4 - A4 - E4 - - -", ('A2', 'A3')),
    ("D4 - F4 - A4 - D5 - E5 - D5 - C5 - A4 -", ('D3', 'D4')),
    ("B4 - - - G#4 - - - E4 - G#4 - B4 - - -", ('E2', 'E3')),
    ("F4 - A4 - D5 - - - C5 - A4 - F4 - - -", ('D3', 'D4')),
    ("E4 - A4 - C5 - - - E5 - D5 - C5 - - -", ('A2', 'A3')),
    ("B4 - - - E5 - - - D5 - C5 - B4 - G#4 -", ('E2', 'E3')),
    ("A4 - - - - - - - E4 - - - A4 - . -", ('A2', 'A3')),
]
for i, (lead, ch) in enumerate(B):
    title.append((lead, bass8(*ch), DR_FILL if i == 7 else DR_B))

board = [  # a board is won: rising fanfare
    ("C4 E4 G4 C5 - - E5 - - - - - D5 - E5 -", "C3 - - - G3 - - - C3 - C4 - G2 - G3 -", "K . . . S . . . K . K . S . S ."),
    ("G5 - - - - - - - E5 - - - . - - -", "C3 - C4 - C3 - C4 - C3 - - - . - - -", "K . . . S . K . K . . . . . . ."),
]
game = [  # a game is won
    ("A4 - C5 - E5 - - - D5 - C5 - D5 - E5 -", bass8('F2', 'F3'), "K . H . S . H . K . K . S . H ."),
    ("G4 - B4 - D5 - - - C5 - B4 - C5 - D5 -", bass8('G2', 'G3'), "K . H . S . H . K . K . S . H ."),
    ("E5 - - - C5 - - - G4 - C5 - E5 - - -", bass8('C3', 'C4'), "K . H . S . H . K . K . S . T ."),
    ("C5 - - - - - - - G5 - - - - - . -", "C3 - - - - - - - C3 - - - . - - -", "K . . . S . . . K . . . . . . ."),
]
match = A[:4] + [  # the match is won: the theme, ending on a big major chord
    ("E5 - - - D5 - C5 - B4 - - - A4 - - -", ('F2', 'F3')),
    ("D5 - - - B4 - G4 - B4 - D5 - - - - -", ('G2', 'G3')),
    ("C5 - E5 - G5 - - - - - - - E5 - - -", ('C3', 'C4')),
    ("C5 - - - - - - - - - - - . - - -", ('C3', 'C3')),
]
match_bars = [(lead, bass8(*ch), DR_FILL if i in (5,) else DR_A) for i, (lead, ch) in enumerate(match)]
match_bars[-1] = (match_bars[-1][0], "C3 - - - - - - - - - - - . - - -", "K . . . S . . . K . . . . . . .")


out = [
    '; Carrom Arena music generated by music.py',
    '; blocking songs use a callable adaptation of utz nanobeep',
    '; source authority: tuklusan/ZX-Spectrum-1-Bit-Routines/nanobeep',
]
out += nb_song('SONG_TITLE', 320, title, loop_bar=4)
out += nb_song('SONG_BOARD', 250, board)
out += nb_song('SONG_GAME', 270, game)
out += nb_song('SONG_MATCH', 285, match_bars)

# ---------------------------------------------------------------- in-game groove
# A long, original Bollywood-EDM-inspired loop for the interrupt-driven player
# in groove.asm.  One bright plucked voice rides punchy kick/snare/hat patterns;
# the melody uses minor-key semitone turns, octave answers and syncopated hooks.
# It is deliberately genre-inspired rather than based on any existing song.
#
# Steps are sixteenths, GM_STEPF frames each (6 frames = 125 BPM).  Thirty-two
# bars make the full loop about 61 seconds long before it repeats.
# Step byte: bits 7-6 drum (0 none, 1 kick, 2 snare, 3 hat), bits 5-0 note (0 none).
GM_STEPF = 6
CPU = 3500000
ENV_MS = [4.2, 2.8, 1.7, 0.9]
DUTY = [7, 11, 18, 30]

def freq(name):
    return hz(name)

gnotes = []
def gn(name):
    if name not in gnotes:
        gnotes.append(name)
    return gnotes.index(name) + 1

GDR = {'.': 0, 'K': 1, 'S': 2, 'H': 3}
def gbar(notes, drums):
    N, D = notes.split(), drums.split()
    assert len(N) == len(D) == 16, (notes, drums)
    return [(GDR[d] << 6) | (0 if n == '.' else gn(n)) for n, d in zip(N, D)]

# The drum byte can trigger one sound per sixteenth, so the patterns alternate
# kick, backbeat and hat rather than trying to fake simultaneous kit voices.
D_A = "K H . H S H K H K H . H S H K H"
D_B = "K H K H S H . H K H K H S H . H"
D_C = "K . H H S H K . K H . H S H K H"
D_D = "K H . H S H K H . H K H S H K H"
D_FILL = "K H K H S H K H K S K S K S K S"
D_DROP = "K . . H S . . H K . . H S . K H"

# 32 bars / ~61 s.  Sections: hook A, answer B, drop/break, final lift.
# The A harmonic-minor G# and occasional Bb give it an Indian-pop colour while
# the four-on-the-floor pulse and octave hooks keep the EDM drive.
GROOVE = [
    ("A4 . A5 E5 . C5 B4 . A4 . E5 A5 . G#5 E5 .", D_A),
    ("F4 . F5 C5 . A4 G4 . F4 . C5 F5 . E5 C5 .", D_B),
    ("C5 . G5 C6 . E5 D5 . C5 . G5 E5 . D5 G5 .", D_A),
    ("G4 . G5 D5 . B4 A4 . G4 . D5 G5 . B4 D5 .", D_FILL),

    ("A4 . E5 A5 . C6 B5 . A5 . E5 C5 . B4 G#4 .", D_B),
    ("F4 . C5 F5 . A5 G5 . F5 . C5 A4 . G4 E4 .", D_C),
    ("C5 . E5 G5 . C6 G5 . E5 . D5 E5 . G5 E5 .", D_A),
    ("G4 . B4 D5 . G5 F5 . D5 . B4 A4 . G4 D5 .", D_FILL),

    ("D5 . A5 D6 . F5 E5 . D5 . A5 F5 . E5 C5 .", D_A),
    ("A4 . C5 E5 . A5 G#5 . E5 . C5 B4 . A4 E5 .", D_B),
    ("E4 . B4 E5 . G#5 B5 . E6 . B5 G#5 . F5 E5 .", D_C),
    ("A4 . . A5 . E5 . C5 . B4 . G#4 . E4 . .", D_DROP),

    ("A4 C5 E5 A5 . E5 C5 . B4 C5 E5 . G#5 E5 C5 .", D_A),
    ("F4 A4 C5 F5 . C5 A4 . G4 A4 C5 . E5 C5 A4 .", D_B),
    ("C5 E5 G5 C6 . G5 E5 . D5 E5 G5 . B5 G5 E5 .", D_A),
    ("G4 B4 D5 G5 . D5 B4 . A4 B4 D5 . F5 D5 B4 .", D_FILL),

    ("A4 . E5 . A5 . C6 . B5 . A5 . E5 . C5 .", D_DROP),
    ("A#4 . F5 . A#5 . D6 . C6 . A#5 . F5 . D5 .", D_DROP),
    ("A4 . E5 A5 . C6 B5 A5 G#5 . E5 C5 B4 . E5 .", D_D),
    ("E4 . B4 E5 . G#5 B5 E6 . D6 B5 G#5 E5 . E5 .", D_FILL),

    ("A4 . A5 E5 . C5 B4 . A4 C5 E5 A5 . G#5 E5 C5", D_B),
    ("F4 . F5 C5 . A4 G4 . F4 A4 C5 F5 . E5 C5 A4", D_A),
    ("D5 . D6 A5 . F5 E5 . D5 F5 A5 D6 . C6 A5 F5", D_C),
    ("E4 . E5 B4 . G#4 B4 . E5 G#5 B5 E6 . D6 B5 G#5", D_FILL),

    ("A4 C5 E5 A5 C6 B5 A5 E5 C5 . B4 C5 E5 G#5 E5 C5", D_A),
    ("F4 A4 C5 F5 A5 G5 F5 C5 A4 . G4 A4 C5 E5 C5 A4", D_B),
    ("C5 E5 G5 C6 E6 D6 C6 G5 E5 . D5 E5 G5 B5 G5 E5", D_C),
    ("G4 B4 D5 G5 B5 A5 G5 D5 B4 . A4 B4 D5 F5 D5 B4", D_FILL),

    ("D5 . F5 A5 . D6 C6 . A5 . F5 E5 . D5 A5 .", D_A),
    ("E4 . G#4 B4 . E5 G#5 . B5 . G#5 F5 . E5 B4 .", D_B),
    ("A4 . C5 E5 . A5 C6 . E6 . C6 A5 . E5 C5 .", D_D),
    ("A4 . E5 A5 . C6 B5 A5 G#5 E5 C5 B4 A4 . E5 A5", D_FILL),
]

pats, order = [], []
for notes, dr in GROOVE:
    bar = gbar(notes, dr)
    if bar not in pats:
        pats.append(bar)
    order.append(pats.index(bar))

out += ["", "; in-game Bollywood-EDM-inspired groove for groove.asm (generated by music.py)",
        f"GM_STEPF EQU {GM_STEPF}", "GM_SONG:"]
out += [f"        dw GM_PAT{i}" for i in order] + ["        dw 0"]
for i, bar in enumerate(pats):
    out.append(f"GM_PAT{i}:  db " + ",".join(str(b) for b in bar))
out.append("; per note (16 bytes): nanobeep-style phase increment, 4 envelope burst lengths, padding")
out.append("GM_NOTES:")
for name in gnotes:
    inc = nb_inc(name)
    out.append(f"        db {inc},34,24,15,8,0,0,0,0,0,0,0,0,0,0,0   ; {name} {freq(name):.0f} Hz")
open(os.path.join(HERE, 'music.asm'), 'w').write("\n".join(out) + "\n")
print(f"music.asm written: {len(GROOVE)} bars, ~{len(GROOVE) * 16 * GM_STEPF / 50:.1f}s loop")
