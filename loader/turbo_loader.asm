; Fixed-sequence turbo loader for ZX Spectrum 48K.
; Loaded inside a BASIC REM line at a fixed address.
; Sequence: loading screen, game, then CALL 32768.
; Each fast data bit is one edge interval: zero 855 T, one 1710 T.

        ORG 0xFB00

PILOT_MIN   EQU 20
SYNC_MIN    EQU 3
BIT_SPLIT   EQU 20

; 35 bytes — Loads screen then game and leaves a safe road back to BASIC.
loader_start:
        di
        ld hl,0x4000
        ld ix,6912
        call load_block
        jr c,load_error

        ld hl,0x8000
        ld ix,24569
        call load_block
        jr c,load_error

        ld sp,0x7FF0
        ld hl,0x7F00
        push hl
        jp 0x8000

; 8 bytes — Paints an error border and retreats to BASIC with dignity.
load_error:
        ld a,2
        out (0xFE),a
        ei
        jp 0

; HL destination, IX payload byte count.
; Reads one fixed fast block, then verifies two rolling checksum bytes.
; 126 bytes — Finds the leader, checks the sums, and gives the border a tiny disco.
load_block:
        xor a
        ld (sum1),a
        ld (sum2),a

        in a,(0xFE)
        and 0x40
        ld c,a
        xor a
        ld d,a

leader_scan:
        call wait_edge
        jr c,block_fail
        cp PILOT_MIN
        jr c,leader_short
        ld a,d
        cp 250
        jr nc,leader_scan
        inc d
        jr leader_scan

leader_short:
        ld e,a
        ld a,d
        cp 16
        jr c,leader_restart
        ld a,e
        cp SYNC_MIN
        jr c,leader_restart
        cp PILOT_MIN
        jr nc,leader_restart

        call wait_edge
        jr c,block_fail
        cp SYNC_MIN
        jr c,leader_restart
        cp PILOT_MIN
        jr nc,leader_restart

payload_loop:
        call read_byte
        jr c,block_fail
        ld (hl),a
        inc hl
        ld e,a

        ld a,(sum1)
        add a,e
        ld (sum1),a
        ld e,a
        ld a,(sum2)
        add a,e
        ld (sum2),a
        and 1
        out (0xFE),a

        dec ix
        ld a,ixh
        or ixl
        jr nz,payload_loop

        call read_byte
        jr c,block_fail
        ld e,a
        ld a,(sum1)
        cp e
        jr nz,block_fail

        call read_byte
        jr c,block_fail
        ld e,a
        ld a,(sum2)
        cp e
        jr nz,block_fail

        or a
        ret

leader_restart:
        xor a
        ld d,a
        jr leader_scan

block_fail:
        scf
        ret

; Return one byte in A. Bits arrive MSB first.
; 22 bytes — Rebuilds one byte from eight turbo edge intervals.
read_byte:
        ld e,0
        ld d,8
read_bit:
        call wait_edge
        jr c,read_fail
        cp BIT_SPLIT
        ccf
        rl e
        dec d
        jr nz,read_bit
        ld a,e
        or a
        ret
read_fail:
        scf
        ret

; C holds the last EAR level. Return interval count in A.
; Carry means no edge arrived before timeout.
; 21 bytes — Times one EAR edge and gives up cleanly if the tape sulks.
wait_edge:
        ld b,0
edge_loop:
        inc b
        jr z,edge_timeout
        in a,(0xFE)
        xor c
        and 0x40
        jr z,edge_loop
        ld a,c
        xor 0x40
        ld c,a
        ld a,b
        or a
        ret
edge_timeout:
        scf
        ret

sum1:   db 0
sum2:   db 0
loader_end:
