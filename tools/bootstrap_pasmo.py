#!/usr/bin/env python3
"""Build the authoritative tuklusan/pasmo fork from source."""
from pathlib import Path
import shutil, subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'tools' / 'pasmo-build'
REPO = 'https://github.com/tuklusan/pasmo.git'
PIN = 'ef6d399c770a30fbd8bdaa7272ccc7e2b0bcf0dd'


def run(*a, cwd=None):
    print('+', ' '.join(map(str, a)))
    subprocess.run([str(x) for x in a], cwd=cwd, check=True)


def main():
    if DEST.exists():
        shutil.rmtree(DEST)
    run('git', 'clone', REPO, DEST)
    run('git', 'checkout', PIN, cwd=DEST)
    # Use Pasmo's own generated configure/Makefile path. Besides tracking the
    # upstream source list, this supplies the VERSION define expected by pasmo.cpp.
    run('./configure', cwd=DEST)
    run('make', '-j2', cwd=DEST)
    run(DEST / 'pasmo', '--version')
    print(DEST / 'pasmo')


if __name__ == '__main__':
    main()
