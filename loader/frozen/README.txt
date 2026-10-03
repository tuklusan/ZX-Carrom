Locked tape inputs.

The files in this directory were copied from the accepted release before the
turbo-loader rewrite:

- loading.scr: 6912 bytes
- game.bin: 24565 bytes

The normal build still assembles the game and regenerates the loading screen,
then compares both outputs byte-for-byte with these files.  The fast-tape
builder consumes these locked copies.  Any future change to either visual or
game code must deliberately replace the matching locked file.

SHA-256:
- game.bin: 64dd0b52bb48a95d57ff39106254368fa9c5776e4216f7f437825852e706dbfa
- loading.scr: dc5220f576a90fad6d17723caa92f483f282f97432f8a612f3f62e2c39e13fc5
