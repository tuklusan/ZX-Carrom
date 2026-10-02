# Carrom Arena ZX

Carrom Arena is a ZX Spectrum 48K machine-code game in which four autonomous robot players play doubles carrom.

Upstream project: `https://github.com/tuklusan/carrom-arena`. The production build is source-first: it assembles the game and the adapted turbo-loader bootstrap with Pasmo, builds both tape formats, and rejects structural mismatches.

## Build

The normal build entry point is:

```text
python3 build.py
```

It requires:

- Python 3;
- **Pasmo** from `https://github.com/tuklusan/pasmo`, on `PATH` or selected with `PASMO=/path/to/pasmo`;
- the command-line **ZQLoader** host tool from `https://github.com/tuklusan/zqloader`, on `PATH` or selected with `ZQLOADER=/path/to/zqloader`.

Generated font, board-table, and music assets are checked in. `python3 build.py --regen-assets` regenerates them and additionally needs Pillow, NumPy, and SkoolKit from `https://github.com/tuklusan/skoolkit`.

`tools/prepare_pasmo.py` deterministically flattens the hand-maintained game sources and converts old local-label/directive conveniences into Pasmo-compatible assembly. `tools/build_zqloader_pasmo.py` does the corresponding deterministic preparation for the adapted 48K ZQLoader bootstrap; the historical loader TAP from the handoff is comparison material only and is never a production input; `dist/reference/README.md` records its hash.

The clean Ubuntu GitHub Actions build pins and compiles the Pasmo fork and ZQLoader host tool from source, runs two production builds, compares their game binary/TAP/TZX/release ZIP byte-for-byte, validates the tape structures, records SHA-256 hashes, and uploads the release artifact.

## Repository vocabulary gate

This repository includes tracked local hooks plus the same checker in the build workflow. Activate the hooks once in each clone:

```text
git config core.hooksPath .githooks
```

The local checks reject restricted vocabulary in the complete staged index and in the proposed commit message. The build workflow repeats the check against the committed tree and current commit message, so bypassing a local hook does not produce a passing build.

## Release files

A successful build creates:

- `dist/carrom.tap` — standard ROM-speed Spectrum TAP;
- `dist/carrom_fast.tzx` — ZQLoader-based turbo TZX at exactly 2x ROM data timing.

`tools/package_release.py dist/zx-carrom.zip` makes the deterministic source-plus-release archive. No WAV release artifact is produced.

The TAP validator checks framing, all XOR checksums, the BASIC header/data pair, the CODE header/data pair, machine-code length, load address `$8000` (32768), entry point 32768, and exact equality between the TAP CODE payload and the freshly assembled binary.

The final TZX is independently parsed and must contain:

- ROM pilot 1: **512 pulses**;
- ROM pilot 2: **512 pulses**;
- fast leader: **256 pulses at 10000 T-states each**;
- turbo zero pulse: **855 T-states**;
- turbo one pulse: **1710 T-states**;
- no explicit pause blocks;
- **0 ms** pause on every data block.

ZQLoader adds its normal 64-T-state end-of-byte delay to the final data pulse of each byte. `loader/tzx19to13.py` also preserves the fix that shortens the initial fast leader across the whole contiguous `0x13` pulse stream, not merely the first 255-pulse TZX chunk.

## Audio

The audio authority is `https://github.com/tuklusan/ZX-Spectrum-1-Bit-Routines`. The bundled provenance and BSD-style upstream licence are under `vendor/ZX-Spectrum-1-Bit-Routines/`.

- Title/result music uses a callable nanobeep-family player derived from the utz/irrlicht-project routines.
- Live game music uses an interrupt-safe 50 Hz phase-accumulator design so play continues while music runs.
- The live track is an original 32-bar Bollywood/EDM-inspired loop at about 125 BPM. At 512 six-frame steps it repeats after about **61.44 seconds**.
- Short game effects use the same general 1-bit synthesis family rather than the old BuzzKick/unrelated-effects mixture.

## Controls and play

Four robot players operate autonomously; RED is North/South and BLUE is East/West.

- **SPACE** — pause/resume
- **F** — fast/normal play
- **M** — cycle sound modes (music+effects, effects only, silent)
- **R** — restart the match
- **Q** — restore normal Spectrum interrupt state and return to BASIC

## Memory map

The main program starts at `$8000`. Board pixels use `$E000-$F7FF`, board attributes `$F800-$FAFF`, the IM2 jump/vector area is `$FDFD/$FE00`, and the game stack is below `$FDF0`. The BASIC loader uses `CLEAR 32767` and starts the machine code with `RANDOMIZE USR 32768`.

## Project layout

- `src/` — game, physics, robots, rendering, generated assets, and audio source.
- `loader/` — adapted ZQLoader source, licence, and TZX finalizer.
- `tools/` — Pasmo preparation/build helpers, tape builders/validators, simulator, and deterministic packager.
- `vendor/ZX-Spectrum-1-Bit-Routines/` — upstream audio reference, provenance, and licence.
- `dist/reference/` — hashes/provenance for historical comparison tapes; never accepted release output.
- `build/` — disposable build products (untracked).
- `dist/` — accepted release outputs after a successful build.

## Verification status

The repository validators are designed to fail on malformed TAP/TZX data or on timing/leader/pause regressions. A release is only described as runtime-accepted after the standard TAP and fast TZX have been exercised in a ZX Spectrum 48K emulator with normal tape playback and the robot/game/audio/control checks have passed. Emulator results are documented as emulator results; no real-hardware claim is made without real-hardware testing.

## Credits and licences

Carrom Arena © 2026 Supratim Sanyal of SANYALnet Labs, under the SANYALnet Labs Non-Commercial License used by the original project.

The 1-bit audio work derives techniques/code from the utz/irrlicht-project `ZX-Spectrum-1-Bit-Routines` collection; see the bundled upstream licence and `PROVENANCE.md`. ZQLoader is by Daan Scherft (Oxidaan) and is retained under its MIT licence; see `loader/ZQLOADER_LICENSE.txt`.
