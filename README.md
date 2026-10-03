# Carrom Arena ZX

Carrom Arena is a ZX Spectrum 48K machine-code game in which four autonomous robot players play doubles carrom.

Upstream project: `https://github.com/tuklusan/carrom-arena`. The build assembles the game and turbo bootstrap with Pasmo, creates the TZX, and stops if the tape structure is wrong.

## Build

The normal build entry point is:

```text
python3 build.py
```

The game is assembled with **Pasmo** from `https://github.com/tuklusan/pasmo`. Generated font, board-table, and music assets are checked in. `python3 build.py --regen-assets` regenerates them and additionally needs SkoolKit from `https://github.com/tuklusan/skoolkit`.

Every normal build assembles the 24,565-byte game and generates the 6,912-byte loading screen from scratch. Their SHA-256 values are checked against the expected values before the TZX is built, so accidental payload changes fail immediately without keeping duplicate binary copies in the source tree.

The clean Ubuntu workflow builds Pasmo from the pinned fork, performs two clean production builds, compares game/TZX/release ZIP byte-for-byte, validates the TZX, records SHA-256 hashes, and checks the exact TZX in Fuse before the longer play checks.

## Repository vocabulary gate

This repository includes tracked local hooks plus the same checker in the build workflow. Activate the hooks once in each clone:

```text
git config core.hooksPath .githooks
```

The local checks reject restricted vocabulary in the complete staged index and in the proposed commit message. The build workflow repeats the check against the committed tree and current commit message, so bypassing a local hook does not produce a passing build.

## Delivery rule

Release files live in `dist/` on `main`, not only in temporary job output. A release is complete only when the tracked files in `dist/` match a fresh checked build. Workflow copies are just for convenience; the files in `dist/` are the release.

## Release files

A successful build creates the sole tape release:

- `dist/carrom_fast.tzx` — compact turbo TZX.

`python3 build.py` creates both `dist/carrom_fast.tzx` and the reproducible source-and-release `dist/zx-carrom.zip`. The ZIP excludes TAP files. No WAV release file is produced.

The fast TZX is small and has exactly four blocks:

1. BASIC header — TZX `0x11`, ROM timing, 2824 pilot pulses;
2. BASIC program/data — TZX `0x11`, ROM timing, 2420 pilot pulses;
3. loading screen — compact generalized-data block `0x19`;
4. game — compact generalized-data block `0x19`.

The BASIC REM line contains a 32-byte bootstrap plus a padded copy of the fast decoder. The bootstrap, assembled from `loader/turbo_bootstrap.asm`, copies the decoder to uncontended RAM at `$FB00`, installs a three-byte return stub at `$7F00`, and jumps to the high copy. The decoder, assembled from `loader/turbo_loader.asm`, loads and checks the screen, loads and checks the game, installs the safe return address, then jumps to 32768. There is no next-block step after the game.

Fast-block requirements are:

- fast leader: **256 pulses at 1710 T-states each**;
- zero data pulse: **855 T-states**;
- one data pulse: **1710 T-states**;
- one edge interval per data bit;
- sync pulses: **667 / 735 T-states**;
- no explicit pause blocks;
- every block pause: **0 ms**.

Each fast payload carries two rolling checksum bytes. During payload transfer the border is driven only black or blue from the rolling checksum parity, once per loaded byte and outside the edge-timing loop. A failed transfer returns from the loader with a red border instead of continuing to consume tape data.

`tools/validate_tzx.py` independently checks the complete four-block structure, ROM pilots, fast leaders, pulse timings, zero pauses, resident-loader bytes, freshly generated screen bytes, freshly assembled game bytes, both checksums, and the absence of anything after the game block.

## Audio

Audio code is based on `https://github.com/tuklusan/ZX-Spectrum-1-Bit-Routines`. A copy of the upstream `nanobeep/main.asm` used as a reference, plus its BSD-style licence, is under `vendor/ZX-Spectrum-1-Bit-Routines/`.

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

The main program starts at `$8000`. Board pixels use `$E000-$F7FF`, board attributes `$F800-$FAFF`, the IM2 jump/vector area is `$FDFD/$FE00`, and the game stack is below `$FDF0`. The TZX auto-runs the resident bootstrap at 23784, copies the timing-critical decoder to `$FB00`, and puts its post-game reset stub at `$7F00`. The decoder is no longer needed once the game has started.

## Project layout

- `src/` — game, physics, robots, rendering, generated assets, and audio source.
- `loader/turbo_bootstrap.asm` — resident BASIC bootstrap that relocates the decoder.
- `loader/turbo_loader.asm` — production fixed-sequence decoder, executed from uncontended high RAM.
- `loader/ZQLOADER_LICENSE.txt` — loader credit and licence.
- `tools/` — screen/TZX builders, validators, simulator, Pasmo preparation, and ZIP packager.
- `vendor/ZX-Spectrum-1-Bit-Routines/` — upstream audio source copy and licence.
- `build/` — disposable build products, never shipped.
- `dist/` — accepted TZX, release ZIP, and hashes.

## Verification status

Testing is emulator-based; no real-hardware claim is made. The workflow first requires the exact TZX to reach game entry in Fuse both with normal settings and with loader acceleration disabled. The generalized blocks are expanded only for the secondary cycle-level snapshot tool used by the longer checks.

Because the new loader has a fixed two-payload sequence, reaching game entry means the complete final payload and its checksum have already been consumed. The TZX validator also proves that the game block is physically the final tape block.

The run-time harness exercises all four robot seats, turn progression, repeated strikes, a complete live-music loop, effects state, sound-mode cycling, pause/resume, fast/normal switching, restart, screen cleanliness, and return to BASIC.

## Credits and licences

Carrom Arena © 2026 Supratim Sanyal of SANYALnet Labs, under the SANYALnet Labs Non-Commercial License used by the original project.

The 1-bit audio work uses techniques and code from the utz/irrlicht-project `ZX-Spectrum-1-Bit-Routines` collection; see the bundled upstream licence and source copy. ZQLoader credit and its MIT licence are in `loader/ZQLOADER_LICENSE.txt`; the release uses the loader sources in `loader/`.
