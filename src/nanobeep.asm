; Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
; Licensed under the SANYALnet Labs Non-Commercial License.

; Carrom Arena callable 2-channel beeper player.
; Based on nanobeep by utz; its licence paperwork is in THIRD_PARTY_LICENSES.txt.
;
; Changes for Carrom Arena:
; - call it with HL pointing at the song layout;
; - no SP-as-sequencer trick, so the caller's stack stays boring;
; - nb_keyexit can bail on any key;
; - per-song loop pointer (0 = one shot);
; - leaves interrupts off; music_play puts the game's IM2 setup back.
;
; Song layout:
;   dw speed
;   dw loop_sequence_or_0
;   dw pattern0_minus_1, pattern1_minus_1, ... , 0
; Pattern rows are two frequency increment bytes, terminated by $FF.
; =============================================================================

; 112 bytes total — Plays the little beeper tunes, because silence was getting smug.
; 23 bytes — Starts the blocking two-voice beeper player and reads its song layout.
nb_play:
        di
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (nb_speed),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (nb_loop),de
        ld (nb_seq),hl
        xor a
        ld d,a                  ; ch1 phase accumulator
        ld c,a                  ; ch2 phase accumulator

; 26 bytes — Fetches the next pattern pointer or loops the song when invited.
nb_next_pattern:
        ld hl,(nb_seq)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (nb_seq),hl
        ld a,d
        or e
        jr nz,nb_have_pattern
        ld hl,(nb_loop)
        ld a,h
        or l
        jr z,nb_stop
        ld (nb_seq),hl
        jr nb_next_pattern

; 3 bytes — Installs a pattern and resets the first channel phase for a clean entrance.
nb_have_pattern:
        ex de,hl                ; HL = pattern-1
        ld d,0                  ; restart ch1 phase at pattern boundary

; 12 bytes — Reads one two-channel row and prepares its duration counter.
nb_row:
        inc hl
        ld a,(hl)
        cp 0xFF
        jr z,nb_next_pattern
        ld e,a                  ; ch1 frequency increment
        inc hl                  ; HL -> ch2 frequency increment
        ld iy,(nb_speed)

; Inner tone core is the nanobeep dual phase-accumulator method.
; 9 bytes — Advances channel one's phase and writes its current beeper state.
nb_tone:
        ld a,d
        add a,e
        ld d,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
; 11 bytes — Spends the calibrated delay before channel two gets its turn.
nb_delay1:
        djnz nb_delay1

        ld a,c
        add a,(hl)
        ld c,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
; 24 bytes — Advances channel two, delays again, and loops for the row duration.
nb_delay2:
        djnz nb_delay2

        dec iy
        ld a,iyh
        or iyl
        jr nz,nb_tone

        ld a,(nb_keyexit)
        or a
        jr z,nb_row
        xor a                   ; A=0 selects all keyboard rows on port FE
        in a,(0xFE)
        cpl
        and 0x1F
        jr z,nb_row

; 4 bytes — Silences the beeper and returns with interrupts still under caller control.
nb_stop:
        xor a
        out (0xFE),a
        ret
