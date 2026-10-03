Locked tape inputs.

The files in this directory were copied from the accepted release before the
turbo-loader rewrite:

- loading.scr: 6912 bytes
- game.bin: 24565 bytes

The normal build still assembles the game and regenerates the loading screen,
then compares both outputs byte-for-byte with these files.  The fast-tape
builder consumes these locked copies.  Any future change to either visual or
game code must deliberately replace the matching locked file.
