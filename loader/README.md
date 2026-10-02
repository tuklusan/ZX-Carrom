# ZQLoader integration

`zqloader_carrom.z80asm` is the retained 48K loader adaptation based on ZQLoader by Daan Scherft / Oxidaan. Its MIT licence is in `ZQLOADER_LICENSE.txt`.

Production does **not** consume a historical loader TAP. `tools/build_zqloader_pasmo.py` deterministically prepares this retained source for Pasmo, assembles its BASIC/REM-resident and relocated-upper portions with Pasmo, writes a fresh bootstrap TAP, and writes the `.exp` symbol file that the ZQLoader host program uses to patch timing/runtime fields.

The previous known-good bootstrap is not used or shipped as current output. Its SHA-256 is recorded in `dist/reference/README.md` for comparison/provenance.

`tzx19to13.py` finalizes ZQLoader's TZX output by:

- expanding generalized-data (`0x19`) blocks to ordinary pulse-sequence (`0x13`) blocks;
- preserving the two cold-loadable ROM pilots at 2824 and 2420 pulses;
- shortening the first complete contiguous fast pulse leader to 256 pulses at 1710 T-states each even when it originally spans several `0x13` chunks;
- forcing per-block pauses to 0 ms; and
- removing explicit pause (`0x20`) blocks.

The production host settings are 855 T-states for a zero and 1710 T-states for a one, exactly half the usual ROM data pulse timing. The no-gap layout and short 256-pulse fast leader must pass emulator tape-playback acceptance before release.
