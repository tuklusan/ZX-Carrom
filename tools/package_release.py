#!/usr/bin/env python3
"""Create a byte-reproducible source + accepted TZX release ZIP."""
from pathlib import Path
import argparse, os, zipfile

ROOT=Path(__file__).resolve().parents[1]
FIXED=(2026,1,1,0,0,0)
EXCLUDE_DIRS={'.git','build','__pycache__','tools/pasmo-build'}
EXCLUDE_FILES={'dist/zx-carrom.zip','dist/SHA256SUMS'}


def include_path(p: Path):
    rel=p.relative_to(ROOT).as_posix()
    if rel in EXCLUDE_FILES: return False
    if p.suffix.lower() == '.tap': return False
    if any(part in EXCLUDE_DIRS for part in p.relative_to(ROOT).parts): return False
    if p.suffix in {'.pyc','.wav','.log'}: return False
    return True


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('output', nargs='?', default='dist/zx-carrom.zip'); a=ap.parse_args()
    out=(ROOT/a.output).resolve() if not Path(a.output).is_absolute() else Path(a.output)
    required=[ROOT/'dist/carrom_fast.tzx']
    for p in required:
        if not p.exists(): raise SystemExit(f'missing accepted release artifact: {p}')
    files=[p for p in ROOT.rglob('*') if p.is_file() and include_path(p) and p.resolve()!=out]
    out.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(files,key=lambda x:x.relative_to(ROOT).as_posix()):
            rel=p.relative_to(ROOT).as_posix()
            zi=zipfile.ZipInfo(rel,FIXED); zi.compress_type=zipfile.ZIP_DEFLATED
            zi.external_attr=(0o755 if os.access(p,os.X_OK) else 0o644)<<16
            z.writestr(zi,p.read_bytes())
    print(f'{out}: {len(files)} files, {out.stat().st_size} bytes')

if __name__=='__main__': main()
