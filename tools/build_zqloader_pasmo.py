#!/usr/bin/env python3
"""Freshly assemble the adapted 48K ZQLoader bootstrap with Pasmo.

The retained loader source uses SjASMPlus DISP and a few syntax conveniences.
This deterministic builder preserves its two-address design by assembling the
REM-resident lower/control part and the relocated upper part separately, then
concatenating the emitted bytes into one BASIC REM payload.  Pasmo is the only
assembler used.
"""
from pathlib import Path
import argparse, re, struct, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'loader' / 'zqloader_carrom.z80asm'
DEFAULT_INC = ROOT / 'loader' / 'zq_basic.inc'
PROG = 23755
UPPER_TOP = 0xFFFF


def run(*args, cwd=None):
    print('+', ' '.join(map(str, args)))
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def active_48k(lines):
    """Resolve only the source's compile-time conditionals for the 48K release."""
    defined = set()  # BANKSWITCH128, DEBUG and DO_COMRESS_PAIRS deliberately off
    out, stack = [], []
    enabled = True
    for raw in lines:
        code = raw.split('//', 1)[0].strip()
        m = re.match(r'^IFDEF\s+([A-Za-z_][A-Za-z0-9_]*)', code, re.I)
        if m:
            cond = m.group(1) in defined
            stack.append((enabled, cond))
            enabled = enabled and cond
            continue
        if re.match(r'^ELSE\b', code, re.I):
            if not stack: raise SystemExit('unmatched ELSE in loader source')
            parent, cond = stack[-1]
            enabled = parent and not cond
            stack[-1] = (parent, not cond)
            continue
        if re.match(r'^ENDIF\b', code, re.I):
            if not stack: raise SystemExit('unmatched ENDIF in loader source')
            parent, _ = stack.pop()
            enabled = parent
            continue
        if enabled:
            out.append(raw)
    if stack:
        raise SystemExit('unterminated IFDEF in loader source')
    return out


def strip_comment(line):
    return line.split('//', 1)[0].rstrip()


def transform_plusstar(line):
    m = re.match(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)\+\*:\s*(ld|jp)\s+([^,\s]+)(?:\s*,\s*(.+))?$', line, re.I)
    if not m:
        return [line]
    indent, label, op, a, b = m.groups()
    op = op.lower(); au = a.upper()
    if op == 'ld' and b is not None:
        op8 = {'C':0x0E, 'H':0x26, 'D':0x16}
        op16 = {'SP':0x31, 'DE':0x11, 'HL':0x21, 'IX':None, 'IY':None}
        if au in op8:
            return [f'{indent}db 0x{op8[au]:02X}', f'{label}: db {b}']
        if au in op16 and op16[au] is not None:
            return [f'{indent}db 0x{op16[au]:02X}', f'{label}: dw {b}']
    if op == 'jp' and b is None:
        return [f'{indent}db 0xC3', f'{label}: dw {a}']
    raise SystemExit(f'unsupported +* patch site: {line}')


def normalize(lines):
    out=[]; in_num2=False
    for raw in active_48k(lines):
        line=strip_comment(raw)
        s=line.strip()
        if not s:
            out.append('')
            continue
        if re.match(r'^NUM2\s+MACRO\b', s, re.I):
            in_num2=True; continue
        if in_num2:
            if re.match(r'^ENDM\b', s, re.I): in_num2=False
            continue
        if re.match(r'^(DEVICE|DEFINE|DISPLAY|EXPORT|EMPTYTAP|SAVETAP|SAVEBIN|ENT)\b', s, re.I):
            continue
        if re.match(r'^IF\s+__ERRORS__', s, re.I):
            continue
        if re.match(r'^ENDIF\b', s, re.I):
            continue
        if re.match(r'^DISP\b', s, re.I):
            continue
        line=re.sub(r'\bDC\b', 'db', line, flags=re.I)
        line=re.sub(r'0b([01]+)', r'%\1', line, flags=re.I)
        line=line.replace('" Loading...\\r"', '" Loading...",13')
        line=line.replace('"ERROR\\r"', '"ERROR",13')
        line=line.replace('"DEBUG\\r"', '"DEBUG",13')
        line=re.sub(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', r'\1\2 EQU \3', line)
        # SjASMPlus permits `label+1:` to export the immediate operand of an
        # instruction.  The 48K loader uses this once for CP n; spell out that
        # opcode so Pasmo can give the patch byte an ordinary label.
        m_cp = re.match(r'^(\s*)(\.[A-Za-z_][A-Za-z0-9_]*)\+1:\s*cp\s+(.+)$', line, re.I)
        if m_cp:
            indent, label, value = m_cp.groups()
            out.extend([f'{indent}db 0xFE', f'{label}: db {value}'])
            continue
        out.extend(transform_plusstar(line))
    # Dot locals: scope them to the nearest preceding explicit global label.
    scope='TOP'; serial=0; final=[]
    glab=re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_$]*):')
    dot=re.compile(r'(?<![A-Za-z0-9_.$])\.([A-Za-z_][A-Za-z0-9_]*)')
    for line in out:
        m=glab.match(line)
        if m:
            scope=m.group(1); serial += 1
        prefix=f'__L{serial}_{re.sub(r"[^A-Za-z0-9_]", "_", scope)}_'
        final.append(dot.sub(lambda m: prefix+m.group(1), line))
    return final


def parse_sym(path):
    syms={}
    for line in Path(path).read_text().splitlines():
        m=re.match(r'^\s*([^\s]+)\s+EQU\s+([0-9A-Fa-f]+)H\s*$', line)
        if m:
            syms[m.group(1)] = int(m.group(2),16)
            continue
        m=re.match(r'^\s*([^\s]+)\s+EQU\s+(?:0x)?([0-9A-Fa-f]+)\s*$', line, re.I)
        if m:
            syms[m.group(1)] = int(m.group(2),16)
    if not syms:
        raise SystemExit(f'could not parse Pasmo symbols: {path}')
    return syms


def eq_lines(syms, exclude=()):
    ex=set(exclude)
    return [f'{k} EQU 0x{v:04X}' for k,v in sorted(syms.items()) if k not in ex and not k.startswith('__')]


def assemble(pasmo, text, stem, td):
    asm=td/f'{stem}.asm'; binp=td/f'{stem}.bin'; sym=td/f'{stem}.sym'
    asm.write_text(text)
    run(pasmo, '--bin', '--pass3', asm, binp, sym, cwd=ROOT)
    return binp.read_bytes(), parse_sym(sym), asm


def tap_block(flag, data):
    payload=bytes([flag])+data
    chk=0
    for b in payload: chk ^= b
    payload += bytes([chk])
    return len(payload).to_bytes(2,'little') + payload


def tap_header(name, length):
    nm=name.ljust(10)[:10].encode('ascii')
    body=bytes([0])+nm+struct.pack('<HHH',length,10,length)
    return tap_block(0, body)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--pasmo', required=True)
    ap.add_argument('--include', default=str(DEFAULT_INC), help='generated zq_basic.inc path')
    ap.add_argument('--tap', default=str(ROOT/'loader'/'zqloader_carrom.tap'))
    ap.add_argument('--exp', default=str(ROOT/'loader'/'zqloader_carrom.exp'))
    ap.add_argument('--compare', default=None, help='optional historical TAP for byte comparison')
    a=ap.parse_args()
    inc = Path(a.include)
    if not inc.exists():
        raise SystemExit(f'{inc} is missing; run tools/mktap.py first')

    raw=SRC.read_text().splitlines()
    try:
        split=next(i for i,l in enumerate(raw) if l.strip().startswith('ASM_UPPER_START_OFFSET:'))
        upper_label=next(i for i,l in enumerate(raw[split:],split) if l.strip()=='ASM_UPPER_START')
        upper_end=next(i for i,l in enumerate(raw[upper_label+1:],upper_label+1) if l.strip().startswith('ASM_UPPER_END'))
    except StopIteration:
        raise SystemExit('could not locate ZQLoader lower/upper split markers')

    lower=normalize(raw[:split])
    lower=[(f'        INCLUDE "{inc.as_posix()}"' if re.match(r'^\s*INCLUDE\s+["\']zq_basic\.inc["\']', l, re.I) else l) for l in lower]
    # CLEAR is synthetic after the final payload size is known.
    lower=[l for l in lower if not re.match(r'^\s*CLEAR\s+EQU\b',l,re.I)]
    # The REM line length crosses the separately assembled upper block.
    lower=[('        dw REM_PAYLOAD_LEN' if 'dw REM_LINE_END - REM_LINE_BEGIN' in l else l) for l in lower]
    lower.append('ASM_UPPER_START_OFFSET:')

    upper=normalize(raw[upper_label+1:upper_end])

    with tempfile.TemporaryDirectory(prefix='zqpasmo-') as t:
        td=Path(t)
        # Lower probe gives addresses/constants needed while sizing upper code.
        lower_probe='\n'.join([
            'ASM_UPPER_START EQU 0xFF00',
            'ASM_UPPER_LEN EQU 0x0100',
            'REM_PAYLOAD_LEN EQU 0',
            *lower, ''
        ])
        lprobe, lsyms0, _=assemble(a.pasmo, lower_probe, 'lower_probe', td)

        upper_probe='\n'.join([
            *eq_lines(lsyms0, exclude={'ASM_UPPER_START','ASM_UPPER_LEN','ASM_UPPER_START_OFFSET'}),
            'ORG 0x8000',
            'ASM_UPPER_START:',
            *upper,
            'ASM_UPPER_END:',
            ''
        ])
        uprobe, _, _=assemble(a.pasmo, upper_probe, 'upper_probe', td)
        upper_len=len(uprobe)
        upper_start=0x10000-upper_len
        if upper_start < 0xC000:
            raise SystemExit(f'ZQLoader upper part too large: {upper_len} bytes')

        lower_pass='\n'.join([
            f'ASM_UPPER_START EQU 0x{upper_start:04X}',
            f'ASM_UPPER_LEN EQU 0x{upper_len:04X}',
            'REM_PAYLOAD_LEN EQU 0',
            *lower, ''
        ])
        lbin0, lsyms1, _=assemble(a.pasmo, lower_pass, 'lower_pass', td)
        total_len=len(lbin0)+upper_len+1
        rem_begin=lsyms1['REM_LINE_BEGIN']
        rem_end=PROG+total_len
        rem_len=rem_end-rem_begin

        lower_final='\n'.join([
            f'ASM_UPPER_START EQU 0x{upper_start:04X}',
            f'ASM_UPPER_LEN EQU 0x{upper_len:04X}',
            f'REM_PAYLOAD_LEN EQU 0x{rem_len:04X}',
            *lower, ''
        ])
        lbin, lsyms, lasm=assemble(a.pasmo, lower_final, 'lower_final', td)
        if len(lbin)!=len(lbin0):
            raise SystemExit('lower loader size changed after final REM length patch')
        start_offset=PROG+len(lbin)
        if lsyms['ASM_UPPER_START_OFFSET'] != start_offset:
            raise SystemExit('ASM_UPPER_START_OFFSET symbol mismatch')

        upper_final='\n'.join([
            *eq_lines(lsyms, exclude={'ASM_UPPER_START','ASM_UPPER_LEN','ASM_UPPER_START_OFFSET','REM_PAYLOAD_LEN'}),
            f'ASM_UPPER_START_OFFSET EQU 0x{start_offset:04X}',
            f'ASM_UPPER_LEN EQU 0x{upper_len:04X}',
            f'ORG 0x{upper_start:04X}',
            'ASM_UPPER_START:',
            *upper,
            'ASM_UPPER_END:',
            ''
        ])
        ubin, usyms, uasm=assemble(a.pasmo, upper_final, 'upper_final', td)
        if len(ubin)!=upper_len or usyms['ASM_UPPER_START']!=upper_start:
            raise SystemExit('upper loader final assembly mismatch')

        payload=lbin+ubin+b'\r'
        if len(payload)!=total_len:
            raise SystemExit('ZQLoader payload length mismatch')
        tap=tap_header('CarromZX',len(payload))+tap_block(0xFF,payload)
        Path(a.tap).write_bytes(tap)

        merged=dict(lsyms); merged.update(usyms)
        merged.update({
            'CLEAR': PROG+len(payload)+256,
            'TOTAL_START': PROG,
            'TOTAL_LEN': len(payload),
            'ASM_UPPER_START_OFFSET': start_offset,
            'ASM_UPPER_START': upper_start,
            'ASM_UPPER_LEN': upper_len,
            'REGISTER_CODE_LEN': 0,
        })
        required=['COPY_ME_SP','COPY_ME_DEST','COPY_ME_SOURCE_OFFSET','COPY_ME_LDDR_OR_LDIR','COPY_ME_END_JUMP',
                  'CLEAR','TOTAL_START','ASM_CONTROL_CODE_START','ASM_CONTROL_CODE_END','ASM_CONTROL_CODE_LEN',
                  'ASM_UPPER_START_OFFSET','ASM_UPPER_START','ASM_UPPER_LEN','HEADER_LEN','TOTAL_LEN','BIT_LOOP_MAX',
                  'BIT_ONE_THESHLD','IO_INIT_VALUE','IO_XOR_VALUE','STACK_SIZE','REGISTER_CODE_LEN']
        missing=[k for k in required if k not in merged]
        if missing: raise SystemExit('missing ZQLoader symbol(s): '+', '.join(missing))
        Path(a.exp).write_text(''.join(f'{k}: EQU 0x{merged[k]:08X}\n' for k in required))

        print(f'{a.tap}: fresh Pasmo ZQLoader, BASIC/REM {len(payload)} bytes; upper {upper_len} bytes @ 0x{upper_start:04X}')
        print(f'{a.exp}: {len(required)} host symbols')
        if a.compare:
            old=Path(a.compare).read_bytes()
            if old==tap:
                print(f'byte-identical to comparison TAP: {a.compare}')
            else:
                n=min(len(old),len(tap)); first=next((i for i in range(n) if old[i]!=tap[i]),n)
                print(f'comparison differs (expected if source/title changed): old={len(old)} new={len(tap)} first_diff={first}')


if __name__=='__main__': main()
