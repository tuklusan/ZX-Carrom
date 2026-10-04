#!/usr/bin/env python3
"""Production boundary guard checks using disposable assembled source copies."""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import check_boundary
import prepare_pasmo


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src'
CHECKER = ROOT / 'tools' / 'check_boundary.py'


def run(cmd, expect_ok=True):
    p = subprocess.run([str(x) for x in cmd], cwd=ROOT,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True)
    if expect_ok and p.returncode:
        raise SystemExit('boundary-guard check failed:\n' + p.stdout)
    if not expect_ok and p.returncode == 0:
        raise SystemExit('boundary-guard check failed: negative case passed\n' + p.stdout)
    return p


def assemble_copy(pasmo, extra, normal_symbols):
    symbols = check_boundary.load_symbols(normal_symbols)
    gap = symbols['BGBUF'] - symbols['vars_end']
    if gap <= 0:
        raise SystemExit('boundary-guard check failed: normal source is already unsafe')
    growth = gap + extra

    with tempfile.TemporaryDirectory(prefix='zx-boundary-') as td:
        td = Path(td)
        src = td / 'src'
        shutil.copytree(SRC, src)
        carrom = src / 'carrom.asm'
        text = carrom.read_text(encoding='utf-8')
        needle = 'vars_end:\n'
        if needle not in text:
            raise SystemExit('boundary-guard check failed: vars_end label not found')
        text = text.replace(needle, f'boundary_probe: ds {growth}\n' + needle, 1)
        carrom.write_text(text, encoding='utf-8')

        old_src = prepare_pasmo.SRC
        try:
            prepare_pasmo.SRC = src
            flat = td / 'carrom_pasmo.asm'
            lines = prepare_pasmo.normalize(prepare_pasmo.flatten(carrom))
            flat.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        finally:
            prepare_pasmo.SRC = old_src

        binary = td / 'carrom.bin'
        sym = td / 'carrom.sym'
        run([pasmo, '--bin', '--pass3', flat, binary, sym])
        return run([sys.executable, CHECKER, sym], expect_ok=False).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pasmo', required=True)
    ap.add_argument('--sym', required=True)
    args = ap.parse_args()

    run([sys.executable, CHECKER, args.sym])
    symbols = check_boundary.load_symbols(args.sym)
    if symbols['vars_end'] >= symbols['BGBUF']:
        raise SystemExit('boundary-guard check failed: normal ordering is unsafe')

    # extra=0 grows exactly to equality; extra=1 crosses by one byte.
    equal_out = assemble_copy(args.pasmo, 0, args.sym)
    cross_out = assemble_copy(args.pasmo, 1, args.sym)
    if 'boundary check failed' not in equal_out or 'boundary check failed' not in cross_out:
        raise SystemExit('boundary-guard check failed: negative diagnostics missing')

    print('boundary-guard production checks: PASS')


if __name__ == '__main__':
    main()
