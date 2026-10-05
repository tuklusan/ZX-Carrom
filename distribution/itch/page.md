# ZX CARROM itch.io release page

## Page settings

**Title:** ZX CARROM for the 48K Sinclair ZX Spectrum

**Project URL:** https://tuklusan.itch.io/zx-carrom

**Short description:** Physics, four shot-planning robots, Queen/Due rules and 1-bit music in a 24,738-byte ZX Spectrum game.

**Classification:** Game

**Kind:** Downloadable

**Release status:** Released

**Genre:** Sports

**Tags:** Carrom, ZX Spectrum, Homebrew, 8-Bit, Retro, Physics, Board Game, Turn-Based, Strategy, Chiptune

**Platforms:** Leave Windows, macOS and Linux unchecked. This is a ZX Spectrum TZX, not a native desktop program.

**Download:** `zxcarrom.tzx` — label it **ZX Spectrum 48K TZX tape image**.

**Cover:** 630x500, using real gameplay. Keep the board, striker, Queen and robot players readable at thumbnail size.

**Screenshots:** Use 3-5 real captures: full board, robot THINKING/aim line, Queen/Due action, loading SCREEN$, and a busy collision or pocketing moment.

**Visibility:** Keep the page private while filling it out. Make it Public only when the cover, screenshots, description and download are all in place.

## Description

# 24,738 bytes. Four robot brains. Twenty moving bodies. One 3.5 MHz Z80.

**ZX CARROM** is a physics-heavy carrom game built for the **48K Sinclair ZX Spectrum**.

The striker moves. Coins collide. Cushions bounce them back. Pockets swallow the lucky ones. Four autonomous robot players study the board, pick their shots and occasionally discover that geometry has opinions.

Under all of that sits Queen-cover drama, Due handling, fouls, returns, board scoring and match play based on the real shape of ICF carrom rules.

And the assembled game payload is **24,738 bytes**.

Yes, bytes.

## Four robots, four ways to cause trouble

Every seat is autonomous. The robots do not just pick a canned angle and hope for divine intervention.

They generate pocket candidates, test shot paths, rank useful options and turn the winning plan into striker position, direction and speed.

The four personalities lean differently:

- **AGGRESSIVE** likes useful attacks.
- **BALANCED** attempts to behave sensibly.
- **DEFENSIVE** is happier making life awkward.
- **TRICKSTER** has a slightly less respectable relationship with angles.

The planner also knows that the Queen changes the value of a shot. If a Queen pocket and a legal cover are both available, it can look ahead rather than treating the red coin as decorative furniture.

## Physics on a machine from 1982

The game runs fixed-point motion for the striker, nine white coins, nine black coins and the Queen.

It handles:

- moving-body substeps;
- board friction;
- cushion rebounds;
- pocket geometry;
- body-to-body collision detection;
- collision normals, impulse and separation;
- returns to the board when the rules demand them; and
- a settling board before the next decision begins.

All of it runs on the Spectrum's **3.5 MHz Z80**.

The processor does not complain. This is mainly because it cannot.

## Queen, cover, Due and the rest of the paperwork

ZX CARROM includes the bits that make carrom more than simply firing discs into holes:

- Queen pocketing and cover;
- Queen returns;
- Due handling;
- striker fouls;
- own and opponent coin returns;
- continuation and turn passing;
- board scoring;
- game and match scoring; and
- four-player doubles turn order.

The rules engine follows the ICF rule structure closely, while staying practical inside a 48K game.

## One-bit music that refuses to know its place

The Spectrum gives us a 1-bit beeper.

ZX CARROM responds with an interrupt-driven, Bollywood/EDM-inspired game loop at about **125 BPM**, running for roughly **61 seconds** before repeating, while the robots and physics keep moving.

There are also short 1-bit sound effects and nanobeep-family title/result music.

It is one bit trying very hard to sound polyphonic. Please do not tell it otherwise.

## Play it

**Play ZX CARROM in your browser:**

https://tuklusan.github.io/zx-spectrum-emulator/?tape=https%3A%2F%2Fraw.githubusercontent.com%2Ftuklusan%2FZX-Carrom%2Fmain%2Fdist%2Fzxcarrom.tzx&autoload=1

Or download **zxcarrom.tzx** below and load it in a ZX Spectrum 48K emulator or compatible setup.

The TZX cold-loads the loading SCREEN$ first, turbo-loads the game second, then starts play.

## Controls

- **SPACE** — pause / resume
- **M** — music + effects / effects only / sound off
- **F** — normal / fast game speed
- **R** — restart the match
- **Q** — return cleanly to BASIC

## Tiny technical bragging section

- Target: **Sinclair ZX Spectrum 48K**
- CPU: **3.5 MHz Z80**
- Game payload: **24,738 bytes**
- Complete release TZX: **32,384 bytes**
- Loading SCREEN$: **6,912 bytes**
- Language: hand-written **Z80 assembly**
- Assembler: **Pasmo**
- Release format: **TZX**
- Robot players: **4**
- Moving bodies: **20**
- Gameplay music: about **125 BPM**, about **61 seconds per loop**
- Source: https://github.com/tuklusan/ZX-Carrom

A lot happens in 24,738 bytes. Apparently spare memory was considered suspicious.

## Credits and licence

ZX CARROM is (c) 2026 Supratim Sanyal of SANYALnet Labs.

Source, licence terms, build instructions and third-party notices are available in the GitHub repository.
