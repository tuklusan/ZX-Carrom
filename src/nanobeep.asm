; =============================================================================
; Carrom Arena callable 2-channel beeper player.
;
; Adapted from nanobeep by utz (ZX-Spectrum-1-Bit-Routines/nanobeep/main.asm).
; Upstream copyright/license is retained in vendor/ZX-Spectrum-1-Bit-Routines.
;
; Changes for Carrom Arena:
; - callable with HL = song descriptor;
; - no SP-as-sequencer trick, so caller stack remains conventional;
; - optional any-key exit via nb_keyexit;
; - per-song loop pointer (0 = one shot);
; - leaves interrupts disabled; music_play restores the game's IM2 state.
;
; Song descriptor:
;   dw speed
;   dw loop_sequence_or_0
;   dw pattern0_minus_1, pattern1_minus_1, ... , 0
; Pattern rows are two frequency increment bytes, terminated by $FF.
; =============================================================================

; 112 bytes — Plays the little beeper tunes, because silence was getting smug.
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

nb_have_pattern:
        ex de,hl                ; HL = pattern-1
        ld d,0                  ; restart ch1 phase at pattern boundary

nb_row:
        inc hl
        ld a,(hl)
        cp 0xFF
        jr z,nb_next_pattern
        ld e,a                  ; ch1 frequency increment
        inc hl                  ; HL -> ch2 frequency increment
        ld iy,(nb_speed)

; Inner tone core is the nanobeep dual phase-accumulator method.
nb_tone:
        ld a,d
        add a,e
        ld d,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
nb_delay1:
        djnz nb_delay1

        ld a,c
        add a,(hl)
        ld c,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
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

nb_stop:
        xor a
        out (0xFE),a
        ret
