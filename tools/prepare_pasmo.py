#!/usr/bin/env python3
"""Flatten Carrom Arena sources and normalize SjASMPlus syntax for Pasmo.

The game sources intentionally retain convenient SjASMPlus-style dot-local and
numeric local labels.  This build-only normalizer scopes them into ordinary
Pasmo identifiers without changing the hand-maintained game sources.
"""
from pathlib import Path
import re, sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src'

inc_re = re.compile(r'^\s*INCLUDE\s+["\']([^"\']+)["\']', re.I)
num_label_re = re.compile(r'^(\s*)(\d+):(.*)$')
num_ref_re = re.compile(r'(?<![A-Za-z0-9_])(\d+)([FB])(?![A-Za-z0-9_])')
dot_token_re = re.compile(r'(?<![A-Za-z0-9_.$])\.([A-Za-z_][A-Za-z0-9_]*)')
normal_label_re = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_$]*):')


def flatten(path: Path, seen=None):
    seen = [] if seen is None else seen
    if path in seen:
        raise SystemExit(f'include cycle: {path}')
    out=[]
    for line in path.read_text().splitlines():
        m=inc_re.match(line)
        if m:
            p=(path.parent/m.group(1)).resolve()
            if not p.exists():
                p=(SRC/m.group(1)).resolve()
            out.extend(flatten(p, seen+[path]))
        else:
            out.append(line)
    return out


def strip_sjasm(lines):
    out=[]
    for line in lines:
        s=line.strip().upper()
        if s.startswith('DEVICE '):
            continue
        if s.startswith('SAVEBIN ') or s.startswith('DISPLAY '):
            continue
        if s.startswith('ASSERT '):
            continue
        out.append(line)
    return out


def numeric_locals(lines):
    defs={}
    mapped={}
    for i,line in enumerate(lines):
        m=num_label_re.match(line)
        if m:
            n=m.group(2)
            k=len(defs.setdefault(n,[]))
            name=f'__N{n}_{k}'
            defs[n].append((i,name))
            mapped[i]=(m.group(1)+name+':'+m.group(3))

    def repl(i,m):
        n,d=m.group(1),m.group(2)
        choices=defs.get(n,[])
        if d=='F':
            for li,name in choices:
                if li>i: return name
        else:
            for li,name in reversed(choices):
                if li<i: return name
        raise SystemExit(f'unresolved numeric label {m.group(0)} on flattened line {i+1}')

    out=[]
    for i,line in enumerate(lines):
        line=mapped.get(i,line)
        out.append(num_ref_re.sub(lambda m: repl(i,m), line))
    return out


def dot_locals(lines):
    """Scope `.foo` labels/references to the nearest preceding global label.

    SjASMPlus accepts dot-local labels. Pasmo does not give dot labels that
    scope, so each source scope receives a deterministic generated prefix.
    Macro-local labels are written with Pasmo LOCAL and therefore never reach
    this transformation as dot identifiers.
    """
    scope='TOP'
    serial=0
    out=[]
    for line in lines:
        # A numeric local has already been converted and should be a scope too.
        m=normal_label_re.match(line)
        if m and not line.lstrip().startswith('.'):
            scope=m.group(1)
            serial += 1
        prefix=f'__D{serial}_{re.sub(r"[^A-Za-z0-9_]", "_", scope)}_'
        out.append(dot_token_re.sub(lambda m: prefix+m.group(1), line))
    return out


def pasmo_expressions(lines):
    """Translate expression operators that Pasmo spells differently."""
    out=[]
    for line in lines:
        code, sep, comment = line.partition(';')
        # Pasmo supports <<, >> and |, but bitwise AND is the word AND.
        code = code.replace('&', ' AND ')
        out.append(code + (sep + comment if sep else ''))
    return out


def normalize(lines):
    return dot_locals(numeric_locals(pasmo_expressions(strip_sjasm(lines))))


def main():
    dest=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'build'/'carrom_pasmo.asm'
    dest.parent.mkdir(parents=True, exist_ok=True)
    lines=normalize(flatten(SRC/'carrom.asm'))
    dest.write_text('\n'.join(lines)+'\n')
    print(dest)

if __name__=='__main__': main()
