#!/usr/bin/env python3
"""Expand generalized TZX blocks to pulse blocks for runtime tools that lack 0x19 support."""
import shutil, struct, subprocess, sys

def u16(b,o): return struct.unpack_from('<H',b,o)[0]
def u24(b,o): return int.from_bytes(b[o:o+3],'little')
def u32(b,o): return struct.unpack_from('<I',b,o)[0]

def block_len(d,o,bid):
    if bid == 0x10: return 4+u16(d,o+2)
    if bid == 0x11: return 18+u24(d,o+15)
    if bid == 0x12: return 4
    if bid == 0x13: return 1+2*d[o]
    if bid == 0x14: return 10+u24(d,o+7)
    if bid == 0x15: return 8+u24(d,o+5)
    if bid == 0x19: return 4+u32(d,o)
    if bid == 0x20: return 2
    if bid in (0x21,0x30): return 1+d[o]
    if bid == 0x22: return 0
    if bid == 0x32: return 2+u16(d,o)
    if bid == 0x5A: return 9
    raise ValueError(f"unsupported TZX block 0x{bid:02X}")

def gdb_pulses(body):
    totp,npp,asp=u32(body,6),body[10],body[11] or 256
    totd,npd,asd=u32(body,12),body[16],body[17] or 256
    p=18
    psyms=[]
    for _ in range(asp if totp else 0):
        flag=body[p]
        if flag & 3: raise ValueError('non-toggle generalized pilot symbol')
        vals=[u16(body,p+1+2*k) for k in range(npp)]
        psyms.append([x for x in vals if x]); p += 1+2*npp
    pulses=[]
    for _ in range(totp):
        sym,rep=body[p],u16(body,p+1); p += 3
        pulses += psyms[sym]*rep
    dsyms=[]
    for _ in range(asd if totd else 0):
        flag=body[p]
        if flag & 3: raise ValueError('non-toggle generalized data symbol')
        vals=[u16(body,p+1+2*k) for k in range(npd)]
        dsyms.append([x for x in vals if x]); p += 1+2*npd
    if totd:
        bits=max(1,(asd-1).bit_length())
        bitpos=0
        for _ in range(totd):
            sym=0
            for _ in range(bits):
                byte=body[p+bitpos//8]
                sym=(sym<<1)|((byte>>(7-bitpos%8))&1)
                bitpos += 1
            pulses += dsyms[sym]
    return pulses

def emit(out,pulses):
    for i in range(0,len(pulses),255):
        chunk=pulses[i:i+255]
        out += bytes([0x13,len(chunk)]) + b''.join(struct.pack('<H',x) for x in chunk)

def check_fuse(src):
    fuse=shutil.which('fuse')
    xvfb=shutil.which('xvfb-run')
    if not fuse or not xvfb:
        print('Fuse exact-tape check skipped: program not installed')
        return
    dbg='\n'.join([
        'delete',
        'breakpoint 32768',
        'commands 1',
        'print 0x4242',
        'exit 0',
        'end',
        'continue',
    ])
    modes=(('default',()),('no-loader-shortcut',('--no-accelerate-loader',)))
    for name,extra in modes:
        cmd=[xvfb,'-a',fuse,'--machine','48','--no-sound','--no-loading-sound',
             '--no-autosave-settings','--no-confirm-actions',*extra,
             '--debugger-command',dbg,src]
        try:
            p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                             text=True,timeout=90)
        except subprocess.TimeoutExpired as e:
            out=e.stdout or ''
            print(out if isinstance(out,str) else out.decode(errors='replace'))
            raise SystemExit(f'Fuse exact-tape check timed out in {name} mode')
        print(p.stdout,end='')
        if p.returncode != 0:
            raise SystemExit(f'Fuse exact-tape check failed in {name} mode: exit {p.returncode}')
        if '0x4242' not in p.stdout:
            raise SystemExit(f'Fuse exact-tape check did not reach 32768 in {name} mode')
        print(f'Fuse exact-tape check: {name} mode reached 32768')

def convert(src,dst):
    d=open(src,'rb').read()
    if d[:8] != b'ZXTape!\x1a': raise SystemExit('bad TZX header')
    out=bytearray(d[:10]); o=10; count=0; pulses=0
    while o < len(d):
        bid=d[o]; o += 1
        ln=block_len(d,o,bid)
        if bid == 0x19:
            body=d[o:o+ln]
            if u16(body,4): raise SystemExit('generalized block has nonzero pause')
            seq=gdb_pulses(body); emit(out,seq); count += 1; pulses += len(seq)
        else:
            out += bytes([bid]) + d[o:o+ln]
        o += ln
    open(dst,'wb').write(out)
    print(f"runtime expansion: {count} generalized block(s), {pulses} pulses")

if __name__ == '__main__':
    if len(sys.argv) != 3: raise SystemExit('usage: expand_tzx_runtime.py IN OUT')
    check_fuse(sys.argv[1])
    convert(sys.argv[1],sys.argv[2])
