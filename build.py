#!/usr/bin/env python3
"""Build Carrom Arena ZX with Pasmo and emit the validated TZX release."""
from pathlib import Path
import argparse, os, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'src'
BUILD = ROOT / 'build'
DIST = ROOT / 'dist'
LOADER = ROOT / 'loader'
FROZEN = LOADER / 'frozen'
TOOLS = ROOT / 'tools'


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
        import PIL  # noqa: F401
        import numpy  # noqa: F401
        import skoolkit  # noqa: F401
    except ImportError as e:
        raise SystemExit('asset regeneration needs Pillow, numpy and SkoolKit: '+str(e))
    run(sys.executable, 'gen.py', cwd=SRC)
    run(sys.executable, 'font64.py', cwd=SRC)
    run(sys.executable, 'music.py', cwd=SRC)


def clean_outputs():
    shutil.rmtree(BUILD, ignore_errors=True)
    BUILD.mkdir(parents=True)
    DIST.mkdir(exist_ok=True)
    for name in ('carrom.tap', 'carrom_fast.tzx'):
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
    if binfile.read_bytes() != (FROZEN / 'game.bin').read_bytes():
        raise SystemExit('game binary differs from locked tape input')

    # Regenerate the loading picture through the internal tape helper, but keep
    # its tape output under build/ only. It is not a release artifact.
    standard_build = BUILD / 'standard'
    standard_build.mkdir()
    internal_tape = standard_build / 'carrom_internal.tap'
    run(sys.executable, TOOLS / 'mktap.py', binfile, internal_tape, standard_build)
    if (standard_build / 'loading.scr').read_bytes() != (FROZEN / 'loading.scr').read_bytes():
        raise SystemExit('loading screen differs from locked tape input')

    fast_bootstrap = BUILD / 'turbo_bootstrap.bin'
    fast_bootstrap_sym = BUILD / 'turbo_bootstrap.sym'
    run(pasmo, '--bin', '--pass3', LOADER / 'turbo_bootstrap.asm', fast_bootstrap, fast_bootstrap_sym)

    fast_loader = BUILD / 'turbo_loader.bin'
    fast_loader_sym = BUILD / 'turbo_loader.sym'
    run(pasmo, '--bin', '--pass3', LOADER / 'turbo_loader.asm', fast_loader, fast_loader_sym)
    run(sys.executable, TOOLS / 'build_fast_tzx.py',
        '--bootstrap', fast_bootstrap,
        '--loader', fast_loader,
        '--screen', FROZEN / 'loading.scr',
        '--game', FROZEN / 'game.bin',
        '--out', DIST / 'carrom_fast.tzx')
    run(sys.executable, TOOLS / 'validate_tzx.py', DIST / 'carrom_fast.tzx',
        '--bootstrap', fast_bootstrap,
        '--loader', fast_loader,
        '--screen', FROZEN / 'loading.scr',
        '--game', FROZEN / 'game.bin')
    print('built and validated:', DIST / 'carrom_fast.tzx')


if __name__ == '__main__':
    main()
