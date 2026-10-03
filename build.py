#!/usr/bin/env python3
"""Build Carrom Arena ZX with Pasmo and emit validated TAP/TZX release files."""
from pathlib import Path
import argparse, os, shutil, subprocess, sys

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
    zqloader = need('ZQLOADER', 'zqloader',
        'Build oxidaan/zqloader and put zqloader on PATH, or set ZQLOADER=/path/to/zqloader.')

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

    # Standard ROM-speed TAP and the small TAP consumed by the ZQLoader host tool.
    loader_build = BUILD / 'loader'
    loader_build.mkdir()
    run(sys.executable, TOOLS / 'mktap.py', binfile, DIST / 'carrom.tap', loader_build)
    run(sys.executable, TOOLS / 'validate_tap.py', DIST / 'carrom.tap', binfile)

    # Assemble the adapted loader bootstrap fresh with Pasmo.  The historical TAP
    # is comparison material only and is never used as production input.
    stub = BUILD / 'zqloader_carrom.tap'
    exp = BUILD / 'zqloader_carrom.exp'
    run(sys.executable, TOOLS / 'build_zqloader_pasmo.py',
        '--pasmo', pasmo, '--include', loader_build / 'zq_basic.inc', '--tap', stub, '--exp', exp)

    raw_tzx = BUILD / 'carrom_zq.tzx'
    run(zqloader,
        'zero_tstates=855', 'one_tstates=1710', 'zero_max=30', 'bit_loop_max=60',
        'outputfile='+str(raw_tzx), '-o', stub, loader_build / 'carrom_code.tap')
    run(sys.executable, LOADER / 'tzx19to13.py', raw_tzx, DIST / 'carrom_fast.tzx')
    run(sys.executable, TOOLS / 'validate_tzx.py', DIST / 'carrom_fast.tzx')
    print('built and validated:', DIST / 'carrom.tap', DIST / 'carrom_fast.tzx')


if __name__ == '__main__':
    main()
