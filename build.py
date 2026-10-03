#!/usr/bin/env python3
"""Build Carrom Arena ZX with Pasmo and emit the validated TZX and release ZIP."""
from pathlib import Path
import argparse, hashlib, os, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'src'
BUILD = ROOT / 'build'
DIST = ROOT / 'dist'
LOADER = ROOT / 'loader'
TOOLS = ROOT / 'tools'

EXPECTED_GAME_SHA = '64dd0b52bb48a95d57ff39106254368fa9c5776e4216f7f437825852e706dbfa'
EXPECTED_SCREEN_SHA = 'dc5220f576a90fad6d17723caa92f483f282f97432f8a612f3f62e2c39e13fc5'


def run(*args, cwd=ROOT):
    print('+', ' '.join(map(str, args)))
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def need(env, exe, hint):
    p = os.environ.get(env) or shutil.which(exe)
    if not p:
        raise SystemExit(f'{exe} not found. {hint}')
    return p


def regen_assets():
    try:
        import skoolkit  # noqa: F401
    except ImportError as e:
        raise SystemExit('asset regeneration needs SkoolKit: ' + str(e))
    run(sys.executable, 'gen.py', cwd=SRC)
    run(sys.executable, 'font64.py', cwd=SRC)
    run(sys.executable, 'music.py', cwd=SRC)


def clean_outputs():
    shutil.rmtree(BUILD, ignore_errors=True)
    BUILD.mkdir(parents=True)
    DIST.mkdir(exist_ok=True)
    for name in ('carrom.tap', 'carrom_fast.tzx', 'zx-carrom.zip'):
        try:
            (DIST / name).unlink()
        except FileNotFoundError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--regen-assets', action='store_true',
                    help='regenerate tables/font/music before assembling')
    a = ap.parse_args()

    pasmo = need('PASMO', 'pasmo',
        'Install/build tuklusan/pasmo and put pasmo on PATH, or set PASMO=/path/to/pasmo.')
    clean_outputs()
    if a.regen_assets:
        regen_assets()

    flat = BUILD / 'carrom_pasmo.asm'
    run(sys.executable, TOOLS / 'prepare_pasmo.py', flat)
    binfile = BUILD / 'carrom.bin'
    sym = BUILD / 'carrom.sym'
    run(pasmo, '--bin', '--pass3', flat, binfile, sym)
    if binfile.stat().st_size >= 0x6000:
        raise SystemExit(f'code too large: {binfile.stat().st_size} bytes')
    game_sha = hashlib.sha256(binfile.read_bytes()).hexdigest()
    if game_sha != EXPECTED_GAME_SHA:
        raise SystemExit(f'game binary hash {game_sha} != expected {EXPECTED_GAME_SHA}')

    loading_screen = BUILD / 'loading.scr'
    run(sys.executable, TOOLS / 'build_loading_screen.py', loading_screen)
    screen_sha = hashlib.sha256(loading_screen.read_bytes()).hexdigest()
    if screen_sha != EXPECTED_SCREEN_SHA:
        raise SystemExit(f'loading screen hash {screen_sha} != expected {EXPECTED_SCREEN_SHA}')

    fast_bootstrap = BUILD / 'turbo_bootstrap.bin'
    fast_bootstrap_sym = BUILD / 'turbo_bootstrap.sym'
    run(pasmo, '--bin', '--pass3', LOADER / 'turbo_bootstrap.asm', fast_bootstrap, fast_bootstrap_sym)

    fast_loader = BUILD / 'turbo_loader.bin'
    fast_loader_sym = BUILD / 'turbo_loader.sym'
    run(pasmo, '--bin', '--pass3', LOADER / 'turbo_loader.asm', fast_loader, fast_loader_sym)
    run(sys.executable, TOOLS / 'build_fast_tzx.py',
        '--bootstrap', fast_bootstrap,
        '--loader', fast_loader,
        '--screen', loading_screen,
        '--game', binfile,
        '--out', DIST / 'carrom_fast.tzx')
    run(sys.executable, TOOLS / 'validate_tzx.py', DIST / 'carrom_fast.tzx',
        '--bootstrap', fast_bootstrap,
        '--loader', fast_loader,
        '--screen', loading_screen,
        '--game', binfile)
    release_zip = DIST / 'zx-carrom.zip'
    run(sys.executable, TOOLS / 'package_release.py', release_zip)
    print('built and validated:', DIST / 'carrom_fast.tzx', release_zip)


if __name__ == '__main__':
    main()
