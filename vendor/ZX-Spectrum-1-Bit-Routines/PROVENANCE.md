# Audio provenance

Canonical source: `tuklusan/ZX-Spectrum-1-Bit-Routines`, branch `master`.

Carrom Arena uses the `nanobeep` 2-channel phase-accumulator technique by utz as
the basis for blocking title/fanfare playback, the interrupt-safe in-game tone
burst, and short phase-based effects. The game adaptation is intentionally not a
byte-for-byte copy: it keeps a conventional caller stack, adds selectable loop
points and any-key exit, and slices background synthesis into 50 Hz interrupt
work so gameplay continues concurrently.

The upstream BSD-style license is in `LICENSE`; the unmodified upstream
`nanobeep/main.asm` snapshot used as the adaptation reference is included under
`nanobeep/`.
