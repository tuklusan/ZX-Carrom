# Carrom Arena ZX

Carrom Arena is a ZX Spectrum 48K machine-code game in which four autonomous robot players play doubles carrom.

Upstream project: `https://github.com/tuklusan/carrom-arena`. The production build is source-first: it assembles the game and the adapted turbo-loader bootstrap with Pasmo, builds both tape formats, and rejects structural mismatches.

## Build

The normal build entry point is:

```text
python3 build.py
```

Production assembly uses **Pasmo** from `https://github.com/tuklusan/pasmo`. Generated font, board-table, and music assets are checked in. `python3 build.py --regen-assets` regenerates them and additionally needs Pillow, NumPy, and SkoolKit from `https://github.com/tuklusan/skoolkit`.

The game and loading picture are locked while tape work is in progress:

- `loader/frozen/game.bin` — 24,565 bytes;
- `loader/frozen/loading.scr` — 6,912 bytes.

Every normal build still assembles the game and regenerates the loading picture, then compares both outputs byte-for-byte with those locked files. The fast-tape builder consumes the locked copies. An accidental game or loading-screen change therefore fails the build rather than silently changing the tape.

The clean Ubuntu workflow builds Pasmo from the pinned fork, performs two clean production builds, compares game/TAP/TZX/release ZIP byte-for-byte, validates both tape formats, records SHA-256 hashes, and checks the exact fast TZX in Fuse before the longer play checks.

## Repository vocabulary gate

This repository includes tracked local hooks plus the same checker in the build workflow. Activate the hooks once in each clone:

```text
git config core.hooksPath .githooks
```

The local checks reject restricted vocabulary in the complete staged index and in the proposed commit message. The build workflow repeats the check against the committed tree and current commit message, so bypassing a local hook does not produce a passing build.

## Delivery rule

Accepted project deliverables are repository content, not temporary job output. Every accepted release must commit its final deliverables under `dist/` on `main`. A release is not complete until the tracked files in `dist/` match a fresh validated build. Workflow artifacts may mirror those files for convenience, but they never replace the committed copies.

## Release files

A successful build creates:

- `dist/carrom.tap` — standard ROM-speed Spectrum TAP;
- `dist/carrom_fast.tzx` — compact turbo TZX.

`tools/package_release.py dist/zx-carrom.zip` makes the deterministic source-plus-release archive. No WAV release artifact is produced.

The standard tape sequence remains BASIC loader, full 6912-byte loading SCREEN$, game CODE, then entry at 32768.

The fast TZX is deliberately fixed and small. It contains exactly four blocks:

1. BASIC header — TZX `0x11`, ROM timing, 512 pilot pulses;
2. BASIC program/data — TZX `0x11`, ROM timing, 512 pilot pulses;
3. loading screen — compact generalized-data block `0x19`;
4. game — compact generalized-data block `0x19`.

The resident loader is assembled directly from `loader/turbo_loader.asm` with Pasmo and lives in a BASIC REM line. Its control flow is fixed: load the screen, verify it, load the game, verify it, then call 32768. It has no next-block state after the game.

Fast-block requirements are:

- fast leader: **256 pulses at 1710 T-states each**;
- zero data pulse: **855 T-states**;
- one data pulse: **1710 T-states**;
- one edge interval per data bit;
- sync pulses: **667 / 735 T-states**;
- no explicit pause blocks;
- every block pause: **0 ms**.

Each fast payload carries two rolling checksum bytes. A failed transfer returns from the loader with a red border instead of continuing to consume tape data.

`tools/validate_tzx.py` independently checks the complete four-block structure, ROM pilots, fast leaders, pulse timings, zero pauses, resident-loader bytes, frozen screen bytes, frozen game bytes, both checksums, and the absence of anything after the game block.

## Audio

The audio authority is `https://github.com/tuklusan/ZX-Spectrum-1-Bit-Routines`. The bundled provenance and BSD-style upstream licence are under `vendor/ZX-Spectrum-1-Bit-Routines/`.

- Title/result music uses a callable nanobeep-family player derived from the utz/irrlicht-project routines.
- Live game music uses an interrupt-safe 50 Hz phase-accumulator design so play continues while music runs.
- The live track is an original 32-bar Bollywood/EDM-inspired loop at about 125 BPM. At 512 six-frame steps it repeats after about **61.44 seconds**.
- Short game effects use the same general 1-bit synthesis family rather than the old BuzzKick/unrelated-effects mixture.

## Controls and play

The shared loading picture uses the 4x8 project font for its key legend. On machine-code entry, the load notice is replaced in place by a flashing small-font prompt. The play screen title is also rendered with the 4x8 font. During play, three independently paced star layers stream outward beside the board, with slower clustered galaxy shapes behind the faster streaks. The east field is confined to its own outer strip, with a safety gap beside the east robot, and the red/yellow/green/cyan ribbon sits at the far-right edge.

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
- `loader/turbo_loader.asm` — production fixed-sequence turbo loader.
- `loader/frozen/` — locked game and loading-screen tape inputs.
- `loader/` — also retains the earlier ZQLoader adaptation and licence for provenance/reference.
- `tools/` — Pasmo preparation, tape builders/validators, simulator, and deterministic packager.
- `vendor/ZX-Spectrum-1-Bit-Routines/` — upstream audio reference, provenance, and licence.
- `dist/reference/` — comparison-only historical material.
- `build/` — disposable build products.
- `dist/` — accepted release outputs after a successful build.

## Verification status

Acceptance is emulator-based; no real-hardware claim is made. The workflow first requires the exact delivered fast TZX to reach game entry in Fuse with loader acceleration disabled. The generalized blocks are expanded only for the secondary cycle-level snapshot tool used by the longer deterministic checks.

Because the new loader has a fixed two-payload sequence, reaching game entry means the complete final payload and its checksum have already been consumed. The TZX validator also proves that the game block is physically the final tape block.

The run-time harness exercises all four robot seats, turn progression, repeated strikes, a complete live-music loop, effects state, sound-mode cycling, pause/resume, fast/normal switching, restart, screen cleanliness, and return to BASIC.

## Credits and licences

Carrom Arena © 2026 Supratim Sanyal of SANYALnet Labs, under the SANYALnet Labs Non-Commercial License used by the original project.

The 1-bit audio work derives techniques/code from the utz/irrlicht-project `ZX-Spectrum-1-Bit-Routines` collection; see the bundled upstream licence and `PROVENANCE.md`. The earlier ZQLoader adapter is retained for provenance under its MIT licence; see `loader/ZQLOADER_LICENSE.txt`. It is no longer used to build the production turbo tape.
