#!/usr/bin/env python3
# Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
# Licensed under the SANYALnet Labs Non-Commercial License.
"""Build Carrom Arena ZX with Pasmo and emit the validated TZX."""
from pathlib import Path
import os, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'src'
BUILD = ROOT / 'build'
DIST = ROOT / 'dist'
LOADER = ROOT / 'loader'
TOOLS = ROOT / 'tools'


def run(*args, cwd=ROOT):
    print('+', ' '.join(map(str, args)))
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def need(env, exe, hint):
    p = os.environ.get(env) or shutil.which(exe)
    if not p:
        raise SystemExit(f'{exe} not found. {hint}')
    return p


def clean_outputs():
    shutil.rmtree(BUILD, ignore_errors=True)
    shutil.rmtree(DIST, ignore_errors=True)
    BUILD.mkdir(parents=True)
    DIST.mkdir(parents=True)


def main():
    pasmo = need('PASMO', 'pasmo',
        'Install/build tuklusan/pasmo and put pasmo on PATH, or set PASMO=/path/to/pasmo.')
    clean_outputs()
    source = SRC / 'carrom.asm'
    binfile = BUILD / 'carrom.bin'
    sym = BUILD / 'carrom.sym'
    run(pasmo, '--bin', '--pass3', source, binfile, sym, cwd=SRC)
    run(sys.executable, TOOLS / 'check_boundary.py', sym)
    game_size = binfile.stat().st_size
    if game_size <= 0:
        raise SystemExit('game binary is empty')
    print(f'game payload: {game_size} bytes')

    loading_screen = BUILD / 'loading.scr'
    run(sys.executable, TOOLS / 'build_loading_screen.py', loading_screen)
    if len(loading_screen.read_bytes()) != 6912:
        raise SystemExit('loading screen size is not 6912 bytes')

    fast_bootstrap = BUILD / 'turbo_bootstrap.bin'
    fast_bootstrap_sym = BUILD / 'turbo_bootstrap.sym'
    run(pasmo, '--bin', '--pass3', LOADER / 'turbo_bootstrap.asm', fast_bootstrap, fast_bootstrap_sym)

    fast_loader = BUILD / 'turbo_loader.bin'
    fast_loader_sym = BUILD / 'turbo_loader.sym'
    run(pasmo, '--bin', '--pass3', '--equ', f'GAME_SIZE={game_size}',
        LOADER / 'turbo_loader.asm', fast_loader, fast_loader_sym)

    tzx = DIST / 'zxcarrom.tzx'
    run(sys.executable, TOOLS / 'build_fast_tzx.py',
        '--bootstrap', fast_bootstrap,
        '--loader', fast_loader,
        '--screen', loading_screen,
        '--game', binfile,
        '--out', tzx)
    run(sys.executable, TOOLS / 'validate_tzx.py', tzx,
        '--bootstrap', fast_bootstrap,
        '--loader', fast_loader,
        '--screen', loading_screen,
        '--game', binfile)
    print('built and validated:', tzx)


if __name__ == '__main__':
    main()
