#!/usr/bin/env python3
"""Fail unless the assembled variable area remains strictly below BGBUF."""
import sys
from pathlib import Path


def parse_value(token):
    token = token.strip()
    if token.lower().startswith('0x'):
        return int(token, 16)
    if token.upper().endswith('H'):
        return int(token[:-1], 16)
    return int(token, 0)


def load_symbols(path):
    symbols = {}
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        parts = line.replace(':', '').split()
        if len(parts) >= 3 and parts[1].upper() == 'EQU':
            try:
                symbols[parts[0]] = parse_value(parts[2])
            except ValueError:
                pass
    return symbols


def check_boundary(path):
    symbols = load_symbols(path)
    missing = [name for name in ('vars_end', 'BGBUF') if name not in symbols]
    if missing:
        raise SystemExit('boundary check missing symbols: ' + ', '.join(missing))
    end = symbols['vars_end']
    limit = symbols['BGBUF']
    if end >= limit:
        raise SystemExit(f'boundary check failed: vars_end={end:04X} BGBUF={limit:04X}')
    print(f'boundary OK: vars_end={end:04X} < BGBUF={limit:04X}')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: check_boundary.py SYMBOL_FILE')
    check_boundary(sys.argv[1])


if __name__ == '__main__':
    main()
