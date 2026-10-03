# Turbo loader

Production uses two Pasmo sources:

- `turbo_bootstrap.asm` — a 32-byte BASIC-resident bootstrap that copies the decoder to `$FB00`, installs the safe return stub at `$7F00`, and jumps to the relocated decoder.
- `turbo_loader.asm` — the fixed-sequence decoder that loads the 6912-byte screen, verifies it, loads the game, verifies it, and jumps to `$8000`.

The accepted TZX uses two ROM-timed bootstrap blocks followed by two compact generalized-data blocks. Fast leaders are 256 pulses at 1710 T-states; data uses 855/1710 T-states; all pauses are zero. The decoder drives the border black or blue once per payload byte, outside the edge-timing loop.

ZQLoader attribution and its MIT licence are retained in `ZQLOADER_LICENSE.txt`.
