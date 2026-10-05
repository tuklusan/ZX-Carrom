; Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
; Licensed under the SANYALnet Labs Non-Commercial License.

; =============================================================================
; In-game groove: a long Bollywood-EDM-inspired beeper loop played from the 50 Hz
; interrupt while the robots play. The tone core is an interrupt-safe adaptation
; of the nanobeep phase-accumulator method from ZX-Spectrum-1-Bit-Routines; drums
; add short kick/noise transients without taking over the CPU for a whole song row.
; The song is 32 bars / about 61 seconds at 125 BPM before looping.
; Sound effects set sfx_busy; the groove keeps time but stays quiet under them.
; The notes and pattern bits live in music.asm; this file just keeps them moving.
; =============================================================================

; 342 bytes total — Keeps the live groove ticking while the robots get on with the match.
; gm_tick deliberately uses AF/BC/DE/HL only and does not touch IX/IY.
; If that ever changes, this interrupt wrapper has to babysit IX/IY too.
; 36 bytes — Ticks frames and the live groove while keeping gameplay's registers out of trouble.
isr:
        push af
        push hl
        ld hl,(frames)
        inc hl
        ld (frames),hl
        ld a,(gm_run)
        or a
        jr z,__D_groove_1_isr_out
        ld a,(music_off)
        ld hl,paused
        or (hl)
        jr nz,__D_groove_1_isr_out
        push bc
        push de
        call gm_tick
        pop de
        pop bc
__D_groove_1_isr_out:   pop hl
        pop af
        ei
        reti

; restart the groove from the top of the song
; 28 bytes — Rewinds the background groove and clears its note and drum ages.
gm_reset:
        ld hl,GM_SONG
        ld (gm_songp),hl
        xor a
        ld (gm_f),a
        ld (gm_left),a
        ld (gm_note),a
        ld (gm_drum),a
        ld a,8
        ld (gm_nage),a
        ld (gm_dage),a
        ret

; 49 bytes — Advances one 50 Hz groove slice unless pause, mute, or an effect says otherwise.
gm_tick:
        ld a,(gm_f)
        or a
        call z,gm_step
        ld a,(gm_f)
        inc a
        cp GM_STEPF
        jr c,__N_groove_1_0
        xor a
__N_groove_1_0:      ld (gm_f),a
        ld a,(sfx_busy)
        or a
        jr nz,__D_groove_3_gm_tick_age
        call gm_drums
        call gm_voice
__D_groove_3_gm_tick_age:   ld hl,gm_dage
        ld a,(hl)
        cp 8
        jr nc,__N_groove_2_0
        inc (hl)
__N_groove_2_0:      ld hl,gm_nage
        ld a,(hl)
        cp 8
        ret nc
        inc (hl)
        ret

; read the next step: a drum and/or a note may start
; 71 bytes — Reads the next sixteenth-step event and starts any note or drum it contains.
gm_step:
        ld a,(gm_left)
        or a
        jr nz,__D_groove_4_gm_step_have
        ld hl,(gm_songp)        ; next pattern
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr nz,__N_groove_1_1
        ld hl,GM_SONG           ; end of song: loop
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
__N_groove_1_1:      ld (gm_songp),hl
        ld (gm_patp),de
        ld a,16
__D_groove_4_gm_step_have:  dec a
        ld (gm_left),a
        ld hl,(gm_patp)
        ld a,(hl)
        inc hl
        ld (gm_patp),hl
        ld c,a
        and 0xC0
        jr z,__N_groove_2_1
        rlca
        rlca
        ld (gm_drum),a
        xor a
        ld (gm_dage),a
__N_groove_2_1:      ld a,c
        and 0x3F
        ret z
        ld (gm_note),a
        xor a
        ld (gm_nage),a
        ret

; 68 bytes — Synthesises kick, snare, or hat from tiny bursts that know when to leave.
gm_drums:
        ld a,(gm_dage)
        ld c,a
        ld a,(gm_drum)
        dec a
        jr z,__D_groove_5_gm_drums_kick
        dec a
        jr z,__D_groove_5_gm_drums_snare
        dec a
        ret nz
        ld a,c                  ; hat: one tiny tick
        or a
        ret nz
        ld b,7
        jp gm_noise
__D_groove_5_gm_drums_snare: ld a,c
        ld b,34
        or a
        jp z,gm_noise
        dec a
        ret nz
        ld b,14
        jp gm_noise
__D_groove_5_gm_drums_kick:  ld a,c
        or a
        ret nz
        ld hl,GM_KICK
        ld c,0x10
__D_groove_5_gm_drums_k:     ld a,(hl)
        or a
        jr z,__D_groove_5_gm_drums_kend
        inc hl
        ld d,a
        ld a,c
        out (0xFE),a
        xor 0x10
        ld c,a
__D_groove_5_gm_drums_kd:    nop
        nop
        dec d
        jr nz,__D_groove_5_gm_drums_kd               ; 24 T per unit
        jr __D_groove_5_gm_drums_k
__D_groove_5_gm_drums_kend:  xor a
        out (0xFE),a
        ret

; falling-pitch kick: half-periods in 24 T units (~2.4 kHz down to ~450 Hz)
GM_KICK: db 30,36,44,54,66,80,96,116,140,162,0

; B samples of sparse ROM noise (two bytes ANDed: ~1/4 density keeps it soft)
; 28 bytes — Turns sparse pseudo-random bytes into a short 1-bit noise burst.
gm_noise:
        ld hl,(gm_np)
__D_groove_7_gm_noise_n:     ld a,(hl)
        inc hl
        and (hl)
        and 0x10
        out (0xFE),a
        ld a,4
__D_groove_7_gm_noise_w:     dec a
        jr nz,__D_groove_7_gm_noise_w
        djnz __D_groove_7_gm_noise_n
        ld a,h
        and 0x1F
        ld h,a
        ld (gm_np),hl
        xor a
        out (0xFE),a
        ret

; plucked voice: short nanobeep-style phase-accumulator burst per interrupt.
; GM_NOTES entry = phase increment, four original envelope burst lengths, padded to 8.
; 51 bytes — Plucks the original phase-accumulator melody over its four-frame envelope.
gm_voice:
        ld a,(gm_note)
        or a
        ret z
        dec a
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,GM_NOTES
        add hl,de
        ld e,(hl)               ; nanobeep phase increment
        inc hl
        ld a,(gm_nage)
        cp 4
        ret nc
        ld c,a
        ld b,0
        add hl,bc
        ld c,(hl)               ; burst iterations for this envelope frame
        xor a
        ld d,a                  ; phase accumulator
__D_groove_8_gm_voice_v:     ld a,d
        add a,e
        ld d,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
        ld b,9
__D_groove_8_gm_voice_vd:    djnz __D_groove_8_gm_voice_vd
        dec c
        jr nz,__D_groove_8_gm_voice_v
        xor a
        out (0xFE),a
        ret
