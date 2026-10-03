; =============================================================================
; In-game groove: a long Bollywood-EDM-inspired beeper loop played from the 50 Hz
; interrupt while the robots play. The tone core is an interrupt-safe adaptation
; of the nanobeep phase-accumulator method from ZX-Spectrum-1-Bit-Routines; drums
; add short kick/noise transients without taking over the CPU for a whole song row.
; The generated song is 32 bars / about 61 seconds at 125 BPM before looping.
; Sound effects set sfx_busy; the groove keeps time but stays quiet under them.
; Song data (GM_SONG, GM_PATn, GM_NOTES, GM_STEPF) comes from music.py.
; =============================================================================

; 343 bytes — Keeps the live groove ticking while the robots get on with the match.
isr:
        push af
        push hl
        ld hl,(frames)
        inc hl
        ld (frames),hl
        ld a,(gm_run)
        or a
        jr z,.out
        ld a,(music_off)
        ld hl,paused
        or (hl)
        jr nz,.out
        push bc
        push de
        call gm_tick
        pop de
        pop bc
.out:   pop hl
        pop af
        ei
        reti

; restart the groove from the top of the song
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

gm_tick:
        ld a,(gm_f)
        or a
        call z,gm_step
        ld a,(gm_f)
        inc a
        cp GM_STEPF
        jr c,1F
        xor a
1:      ld (gm_f),a
        ld a,(sfx_busy)
        or a
        jr nz,.age
        call gm_drums
        call gm_voice
.age:   ld hl,gm_dage
        ld a,(hl)
        cp 8
        jr nc,2F
        inc (hl)
2:      ld hl,gm_nage
        ld a,(hl)
        cp 8
        ret nc
        inc (hl)
        ret

; read the next step: a drum and/or a note may start
gm_step:
        ld a,(gm_left)
        or a
        jr nz,.have
        ld hl,(gm_songp)        ; next pattern
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr nz,1F
        ld hl,GM_SONG           ; end of song: loop
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
1:      ld (gm_songp),hl
        ld (gm_patp),de
        ld a,16
.have:  dec a
        ld (gm_left),a
        ld hl,(gm_patp)
        ld a,(hl)
        inc hl
        ld (gm_patp),hl
        ld c,a
        and 0xC0
        jr z,2F
        rlca
        rlca
        ld (gm_drum),a
        xor a
        ld (gm_dage),a
2:      ld a,c
        and 0x3F
        ret z
        ld (gm_note),a
        xor a
        ld (gm_nage),a
        ret

gm_drums:
        ld a,(gm_dage)
        ld c,a
        ld a,(gm_drum)
        dec a
        jr z,.kick
        dec a
        jr z,.snare
        dec a
        ret nz
        ld a,c                  ; hat: one tiny tick
        or a
        ret nz
        ld b,7
        jp gm_noise
.snare: ld a,c
        ld b,34
        or a
        jp z,gm_noise
        dec a
        ret nz
        ld b,14
        jp gm_noise
.kick:  ld a,c
        or a
        ret nz
        ld hl,GM_KICK
        ld c,0x10
.k:     ld a,(hl)
        or a
        jr z,.kend
        inc hl
        ld d,a
        ld a,c
        out (0xFE),a
        xor 0x10
        ld c,a
.kd:    nop
        nop
        dec d
        jr nz,.kd               ; 24 T per unit
        jr .k
.kend:  xor a
        out (0xFE),a
        ret

; falling-pitch kick: half-periods in 24 T units (~2.4 kHz down to ~450 Hz)
GM_KICK: db 30,36,44,54,66,80,96,116,140,162,0

; B samples of sparse ROM noise (two bytes ANDed: ~1/4 density keeps it soft)
gm_noise:
        ld hl,(gm_np)
.n:     ld a,(hl)
        inc hl
        and (hl)
        and 0x10
        out (0xFE),a
        ld a,4
.w:     dec a
        jr nz,.w
        djnz .n
        ld a,h
        and 0x1F
        ld h,a
        ld (gm_np),hl
        xor a
        out (0xFE),a
        ret

; plucked voice: short nanobeep-style phase-accumulator burst per interrupt.
; GM_NOTES entry = phase increment, then four envelope burst lengths, padded to 16.
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
.v:     ld a,d
        add a,e
        ld d,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
        ld b,9
.vd:    djnz .vd
        dec c
        jr nz,.v
        xor a
        out (0xFE),a
        ret
