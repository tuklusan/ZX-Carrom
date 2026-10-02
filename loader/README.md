# ZQLoader integration

`zqloader_carrom.z80asm` is the retained 48K loader adaptation based on ZQLoader by Daan Scherft / Oxidaan. Its MIT licence is in `ZQLOADER_LICENSE.txt`.

Production does **not** consume a historical loader TAP. `tools/build_zqloader_pasmo.py` deterministically prepares this retained source for Pasmo, assembles its BASIC/REM-resident and relocated-upper portions with Pasmo, writes a fresh bootstrap TAP, and writes the `.exp` symbol file that the ZQLoader host program uses to patch timing/runtime fields.

The previous known-good bootstrap is not used or shipped as current output. Its SHA-256 is recorded in `dist/reference/README.md` for comparison/provenance.

`tzx19to13.py` finalizes ZQLoader's TZX output by:

- preserving compact generalized-data (`0x19`) blocks and patching the fast leader in place;
- preserving the two cold-loadable ROM pilots at 2824 and 2420 pulses;
- shortening the fast leader to 256 pulses at 1710 T-states each inside the compact generalized block, while retaining the legacy multi-`0x13` shortening path for compatibility;
- forcing per-block pauses to 0 ms; and
- removing explicit pause (`0x20`) blocks.

The production host settings are 855 T-states for a zero and 1710 T-states for a one, exactly half the usual ROM data pulse timing. Payload compression is disabled for this release path so a zero-gap transition never depends on finishing a decompression pass before the next leader. The no-gap layout and short 256-pulse fast leader must pass emulator tape-playback acceptance before release.

The resident loader is embedded in BASIC. It first receives the shared 6912-byte loading SCREEN$ at 16384, then the game bytes at 32768, then jumps to 32768. Before that jump it places its normal BASIC cleanup path on the private stack, so the game's Q return restores loader state and reaches BASIC cleanly. The standard tape presents the same screen and game sequence using the ROM loader instead.
