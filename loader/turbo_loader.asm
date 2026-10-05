; Built from ZQLoader by Daan Scherft/Oxidaan.
; MIT licence paperwork lives in ZQLOADER_LICENSE.txt.

; Fixed-sequence turbo loader for ZX Spectrum 48K.
; Loaded inside a BASIC REM line at a fixed address.
; Sequence: loading screen, game, then enter 32768 with a BASIC return route.
; Each fast data bit is one edge interval: zero 855 T, one 1710 T.
; build.py tells us how many bytes the freshly assembled game brought along.

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
        ld ix,GAME_SIZE
        call load_block
        jr c,load_error

        ld sp,0x7E00
        ld hl,0x7F00
        push hl
        jp 0x8000

; 8 bytes — Paints an error border and retreats to BASIC with what dignity remains.
load_error:
        ld a,2
        out (0xFE),a
        ei
        jp 0x7F00

; HL says where the bytes land; IX says how much luggage is coming.
; Reads one fixed fast block, then verifies two rolling checksum bytes.
; 126 bytes total — Finds the leader, checks the sums, and gives the border a tiny disco.
; 14 bytes — Clears both rolling sums and starts hunting for a fast leader.
load_block:
        xor a
        ld (sum1),a
        ld (sum2),a

        in a,(0xFE)
        and 0x40
        ld c,a
        xor a
        ld d,a

; 17 bytes — Counts leader pulses until something shorter finally turns up.
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

; 28 bytes — Checks sync timing, because random tape squeaks do not get a vote.
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

; 61 bytes — Streams payload bytes, updates both sums, and gives the border a twitch.
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

; 4 bytes — Forgets the false start and resumes leader hunting without sulking.
leader_restart:
        xor a
        ld d,a
        jr leader_scan

; 2 bytes — Raises carry and lets the caller handle the bad-news department.
block_fail:
        scf
        ret

; Return one byte in A. Bits arrive MSB first.
; 22 bytes total — Rebuilds one byte from eight turbo edge intervals.
; 4 bytes — Sets up eight incoming bits and hands the fiddly work downstairs.
read_byte:
        ld e,0
        ld d,8
; 16 bytes — Times one turbo bit and shifts it into the byte, most significant first.
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
; 2 bytes — Turns a missing edge into carry, which is cheaper than optimism.
read_fail:
        scf
        ret

; C holds the last EAR level. Return interval count in A.
; Carry means no edge arrived before timeout.
; 21 bytes total — Times one EAR edge and gives up cleanly if the tape sulks.
; 2 bytes — Starts an EAR-edge timer with the full eight-bit patience budget.
wait_edge:
        ld b,0
; 17 bytes — Polls EAR until it changes level or the counter runs out of tea.
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
; 2 bytes — Reports a tape edge that never bothered to arrive.
edge_timeout:
        scf
        ret

sum1:   db 0
sum2:   db 0
loader_end:
