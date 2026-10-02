#!/usr/bin/env python3
"""Build the user's tuklusan/pasmo fork into tools/pasmo-build/pasmo.

This helper intentionally does not download opaque binaries. It clones the named
source repository and compiles the same small C++ source set declared upstream.
"""
from pathlib import Path
import shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'tools' / 'pasmo-build'
REPO = 'https://github.com/tuklusan/pasmo.git'


def run(*a, cwd=None):
    print('+', ' '.join(map(str, a)))
    subprocess.run([str(x) for x in a], cwd=cwd, check=True)


def main():
    if DEST.exists():
        shutil.rmtree(DEST)
    run('git', 'clone', '--depth', '1', REPO, DEST)
    sources = ['asm.cpp','asmfile.cpp','cpc.cpp','pasmo.cpp','pasmotypes.cpp',
               'spectrum.cpp','tap.cpp','token.cpp','trace.cpp','tzx.cpp']
    run('g++', '-O2', '-std=c++11', '-o', 'pasmo', *sources, cwd=DEST)
    print(DEST / 'pasmo')

if __name__ == '__main__':
    main()
