; Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
; Licensed under the SANYALnet Labs Non-Commercial License.

; Carrom Arena ZX - core: maths, screen, rendering, physics.

; 16 bytes per expansion — Steps DE to the next Spectrum pixel row; the layout still thinks it is 1982.
        MACRO DOWN_DE
        LOCAL dd
        inc d
        ld a,d
        and 7
        jr nz,dd
        ld a,e
        add a,32
        ld e,a
        jr c,dd
        ld a,d
        sub 8
        ld d,a
dd:
        ENDM

; ---------------------------------------------------------------- maths
; 458 bytes total — Does the sums so the coins can pretend Newton is watching.

; HL = -HL (preserves BC, DE)
; 8 bytes — Negates HL; two's complement performs its tiny piece of paperwork.
neghl:
        ld a,l
        cpl
        ld l,a
        ld a,h
        cpl
        ld h,a
        inc hl
        ret

; HL = |HL|
; 5 bytes — Makes HL positive, unless it already behaved itself.
abshl:
        bit 7,h
        ret z
        jr neghl

; HL >>= 4 (arithmetic)
; 17 bytes — Arithmetic-shifts HL right four places without calling a meeting.
sra4:
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ret

; A:HL >>= B (arithmetic, 24-bit)
; 9 bytes — Arithmetic-shifts signed A:HL by B bits, one stubborn bit at a time.
sra24:
        sra a
        rr h
        rr l
        djnz sra24
        ret

; A:HL = -A:HL
; 15 bytes — Negates signed A:HL and carries the awkward zero case correctly.
neg24:
        cpl
        ld c,a
        ld a,l
        cpl
        ld l,a
        ld a,h
        cpl
        ld h,a
        inc hl
        ld a,h
        or l
        ld a,c
        ret nz
        inc a
        ret

; HL = B*C unsigned 8x8 via quarter squares. Clobbers A, DE.
; 40 bytes — Multiplies two unsigned bytes with the traditional shift-and-add treadmill.
mul8u:
        ld a,b
        sub c
        jr nc,__N_core_1_0
        neg
__N_core_1_0:      ld l,a
        ld h,0
        add hl,hl
        ld de,QSQ
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,b
        add a,c
        ld l,a
        ld a,0
        adc a,0
        ld h,a
        add hl,hl
        push de
        ld de,QSQ
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        pop de
        or a
        sbc hl,de
        ret

; HL = B*C signed 8x8. Clobbers A, BC, DE.
; 32 bytes — Multiplies signed bytes after separating the signs from the furniture.
smul8:
        ld a,b
        xor c
        ld (m8_sign),a
        ld a,b
        or a
        jp p,__N_core_1_1
        neg
        ld b,a
__N_core_1_1:      ld a,c
        or a
        jp p,__N_core_2_0
        neg
        ld c,a
__N_core_2_0:      call mul8u
        ld a,(m8_sign)
        or a
        ret p
        jp neghl

; A:HL = HL * A (unsigned 16x8 -> 24). Clobbers BC, DE.
; 22 bytes — Multiplies unsigned HL by A and returns the useful low 16 bits.
mul16x8u:
        ex de,hl
        ld hl,0
        ld c,0
        ld b,8
__N_core_1_2:      add hl,hl
        rl c
        rla
        jr nc,__N_core_2_1
        add hl,de
        jr nc,__N_core_2_1
        inc c
__N_core_2_1:      djnz __N_core_1_2
        ld a,c
        ret

; A:HL = HL * A (signed). Clobbers BC, DE.
; 30 bytes — Multiplies signed HL by signed A without pretending signs are optional.
smul16x8:
        ld b,a
        xor h
        ld (m16_sign),a
        bit 7,h
        call nz,neghl
        ld a,b
        or a
        jp p,__N_core_1_3
        neg
__N_core_1_3:      call mul16x8q
        ld b,a
        ld a,(m16_sign)
        or a
        ld a,b
        ret p
        jp neg24
; A:HL = HL * A unsigned, as (H*A)<<8 + L*A with two table multiplies
; 26 bytes — Multiplies signed HL by A and divides by 256 for fixed-point chores.
mul16x8q:
        push hl
        ld b,l
        ld c,a
        push af
        call mul8u              ; L*A
        ex (sp),hl              ; save, HL = A,F
        ld a,h
        pop de                  ; DE = L*A
        pop hl
        push de
        ld b,h
        ld c,a
        call mul8u              ; H*A
        pop de
        ; result = HL<<8 + DE  -> A:HL
        ld a,h
        ld h,l
        ld l,0
        add hl,de
        adc a,0
        ret

; DEHL = BC * DE (unsigned)
; 20 bytes — Multiplies unsigned HL by DE, keeping the low half of the answer.
mul16u:
        ld hl,0
        ld a,16
__N_core_1_4:      add hl,hl
        rl e
        rl d
        jr nc,__N_core_2_2
        add hl,bc
        jr nc,__N_core_2_2
        inc de
__N_core_2_2:      dec a
        jr nz,__N_core_1_4
        ret

; HL = DEHL / BC (unsigned, quotient must fit 16 bits)
; 25 bytes — Divides DE:HL by BC using sixteen rounds of patient subtraction.
div32_16:
        ld a,16
__D_core_13_div32_16_lp:    add hl,hl
        ex de,hl
        adc hl,hl
        jr c,__D_core_13_div32_16_over
        sbc hl,bc
        jr nc,__D_core_13_div32_16_ok
        add hl,bc
        ex de,hl
        jr __D_core_13_div32_16_next
__D_core_13_div32_16_over:  or a
        sbc hl,bc
__D_core_13_div32_16_ok:    ex de,hl
        inc l
__D_core_13_div32_16_next:  dec a
        jr nz,__D_core_13_div32_16_lp
        ret

; HL = HL / C (unsigned 16/8), A = remainder. Clobbers B.
; 15 bytes — Divides HL by C and returns quotient plus the leftover crumbs.
div16_8:
        xor a
        ld b,16
__N_core_1_5:      add hl,hl
        rla
        jr c,__N_core_2_3
        cp c
        jr c,__N_core_3_0
__N_core_2_3:      sub c
        inc l
__N_core_3_0:      djnz __N_core_1_5
        ret

; HL = floor(sqrt(DEHL))
; 11 bytes — Prepares a 32-bit square root and delegates the long division cosplay.
isqrt32:
        ld (sq_n),hl
        ld (sq_n+2),de
        ld b,16
        jr isqrt_core
; A = L = floor(sqrt(HL))  (register digit-by-digit, ~900 T)
; 45 bytes — Prepares a 16-bit square root and normalises it for the shared engine.
isqrt16:
        ld b,8
        ld c,0
        ld de,0
__D_core_16_isqrt16_lp:    add hl,hl
        rl e
        rl d
        add hl,hl
        rl e
        rl d
        sla c
        push hl
        ld h,0
        ld l,c
        add hl,hl
        inc hl
        ex de,hl
        or a
        sbc hl,de
        jr c,__D_core_16_isqrt16_no
        inc c
        ex de,hl
        jr __D_core_16_isqrt16_nx
__D_core_16_isqrt16_no:    add hl,de
        ex de,hl
__D_core_16_isqrt16_nx:    pop hl
        djnz __D_core_16_isqrt16_lp
        ld a,c
        ld l,c
        ld h,0
        ret
; 94 bytes — Extracts an integer square root two bits at a time, because floating point stayed home.
isqrt_core:
        ld hl,0
        ld (sq_root),hl
        ld (sq_rem),hl
        xor a
        ld (sq_rem+2),a
__D_core_17_isqrt_core_lp:    push bc
        ld c,2
__D_core_17_isqrt_core_sh:    ld hl,(sq_n)
        add hl,hl
        ld (sq_n),hl
        ld hl,(sq_n+2)
        adc hl,hl
        ld (sq_n+2),hl
        ld hl,(sq_rem)
        adc hl,hl
        ld (sq_rem),hl
        ld a,(sq_rem+2)
        adc a,a
        ld (sq_rem+2),a
        dec c
        jr nz,__D_core_17_isqrt_core_sh
        ld hl,(sq_root)
        add hl,hl
        ld (sq_root),hl
        xor a
        add hl,hl
        adc a,a
        inc l
        ld c,a
        ex de,hl
        ld hl,(sq_rem)
        or a
        sbc hl,de
        ld a,(sq_rem+2)
        sbc a,c
        jr c,__D_core_17_isqrt_core_no
        ld (sq_rem),hl
        ld (sq_rem+2),a
        ld hl,(sq_root)
        inc hl
        ld (sq_root),hl
__D_core_17_isqrt_core_no:    pop bc
        djnz __D_core_17_isqrt_core_lp
        ld hl,(sq_root)
        ret

; HL = random (xorshift16). Preserves BC, DE.
; 21 bytes — Shakes the tiny xorshift state and hands back its latest bit of mischief.
rand:
        ld hl,(seed)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (seed),hl
        ret

; A = unbiased random 0..C-1 from the 0..127 source range. C must be nonzero.
; Reject the incomplete high bucket before reducing; clobbers HL, B.
; 23 bytes — Uses rejection sampling so awkward divisors do not get biased dice.
rand_n:
        ld hl,128
        call div16_8             ; A = 128 mod C
        ld b,a                   ; size of the rejected tail
__D_core_19_rand_n_retry: call rand
        ld a,l
        and 127
        add a,b
        jp m,__D_core_19_rand_n_retry              ; source >= 128-tail: draw again
        sub b                    ; restore the accepted source value
__D_core_19_rand_n_reduce:
        cp c
        ret c
        sub c
        jr __D_core_19_rand_n_reduce

; ---------------------------------------------------------------- screen
; 101 bytes total — Finds screen rows, restores the board, and flips individual pixels.

; DE = screen address of pixel row C, byte column 0
; 7 bytes — Turns a pixel Y coordinate into the Spectrum's famously sensible screen row.
row_de:
        ld h,ROWLO>>8
        ld l,c
        ld e,(hl)
        inc h
        ld d,(hl)
        ret

; 14 bytes — Copies the pristine board pixels and attributes onto the live screen.
draw_board:
        ld hl,BGBUF             ; pixels then attributes from the clean board buffer
        ld de,0x4000
        ld bc,6912
        ldir
        jp draw_title64

; restore the clean board picture, then forget every piece and seat figure erased by it
; 44 bytes — Restores only the board pixel area while leaving the surrounding stars alone.
reset_board_pixels:
        ld hl,BGBUF
        ld de,0x4000
        ld bc,6912
        ldir
        call draw_title64
        call star_redraw
        ld ix,BODIES
        ld b,NB
__N_core_1_6:      ld (ix+BDRAWN),0
        ld de,BSZ
        add ix,de
        djnz __N_core_1_6
        ld hl,0xFFFF
        ld (robot_drawn),hl
        ld (robot_drawn+2),hl
        ret

; XOR-plot pixel (B=x, C=y)
; 28 bytes — Flips one board pixel through the Spectrum's interleaved screen maze.
plot_xor:
        ld h,ROWLO>>8
        ld l,c
        ld a,b
        rrca
        rrca
        rrca
        and 31
        add a,(hl)
        inc h
        ld h,(hl)
        ld l,a
        ld a,b
        and 7
        add a,BITMASK AND 255
        ld e,a
        ld a,BITMASK>>8
        adc a,0
        ld d,a
        ld a,(de)
        xor (hl)
        ld (hl),a
        ret

BITMASK: db 128,64,32,16,8,4,2,1

; ---------------------------------------------------------------- moving space backdrop
; 555 bytes total — Moves the starfield and draws masked sprites without denting the furniture.
; Outer side strips stream away from the board.  Near/mid/far layers move at
; different frame rates.  Clustered points in the far and mid sets form tiny
; spiral-like galaxies that travel with their layer.

; 98 bytes — Seeds three parallax star layers and a few galaxies without overbooking space.
star_prepare:
        ; remove the old fixed margin dots from the clean board copy
        ld c,24
__D_core_25_star_prepare_prep_row:
        push bc
        call row_de
        ld a,d
        add a,BGOFF>>8
        ld d,a
        xor a
        ld b,5
__D_core_25_star_prepare_prep_l:
        ld (de),a
        inc e
        djnz __D_core_25_star_prepare_prep_l
        ld a,e
        add a,22
        ld e,a
        xor a
        ld b,5
__D_core_25_star_prepare_prep_r:
        ld (de),a
        inc e
        djnz __D_core_25_star_prepare_prep_r
        pop bc
        inc c
        ld a,c
        cp 168
        jr c,__D_core_25_star_prepare_prep_row

        ; the old picture used light paper here.  The moving stars XOR
        ; pixels in columns 28..30, so make their whole lane black-backed.
        ; Column 31 is the ribbon lane and is black except for its four blocks.
        ld hl,BGBUF+6144+3*32+28
        ld b,18
__D_core_25_star_prepare_attr_row:
        ld a,0x47
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld de,28
        add hl,de
        djnz __D_core_25_star_prepare_attr_row

        ; four 4x8 colour blocks at the far-right screen edge
        ld c,80
        ld b,32
__D_core_25_star_prepare_ribbon_px:
        push bc
        call row_de
        ld a,d
        add a,BGOFF>>8
        ld d,a
        ld a,e
        add a,31
        ld e,a
        ld a,(de)
        or 0xF0
        ld (de),a
        pop bc
        inc c
        djnz __D_core_25_star_prepare_ribbon_px
        ld hl,BGBUF+6144+10*32+31
        ld de,32
        ld (hl),0x42
        add hl,de
        ld (hl),0x46
        add hl,de
        ld (hl),0x44
        add hl,de
        ld (hl),0x45
        ret

; 18 bytes — Resets star timing so a new scene starts without inherited drift.
star_reset:
        xor a
        ld (star_far),a
        ld (star_mid),a
        ld (star_near),a
        ld a,(frames)
        ld (star_frame),a
        jr star_redraw

; 27 bytes — Repaints the moving backdrop around the protected board and HUD.
star_redraw:
        ld hl,STAR_FAR
        ld a,(star_far)
        call stars_draw
        ld hl,STAR_MID
        ld a,(star_mid)
        call stars_draw
        ld hl,STAR_NEAR
        ld a,(star_near)
        jp stars_draw

; 114 bytes — Advances parallax layers at their own speeds and wraps the universe cheaply.
star_step:
        ld a,(frames)
        ld b,a
        ld a,(star_frame)
        cp b
        ret z
        ld a,b
        ld (star_frame),a

        ld a,(star_frame)
        and 1
        jr nz,__D_core_28_star_step_far_test
        ld hl,STAR_NEAR
        ld a,(star_near)
        call stars_draw
        ld a,(star_near)
        inc a
        cp 24
        jr c,__D_core_28_star_step_near_store
        xor a
__D_core_28_star_step_near_store:
        ld (star_near),a
        ld hl,STAR_NEAR
        call stars_draw

        ld a,(star_frame)
        and 3
        jr nz,__D_core_28_star_step_far_test
        ld hl,STAR_MID
        ld a,(star_mid)
        call stars_draw
        ld a,(star_mid)
        inc a
        cp 24
        jr c,__D_core_28_star_step_mid_store
        xor a
__D_core_28_star_step_mid_store:
        ld (star_mid),a
        ld hl,STAR_MID
        call stars_draw

__D_core_28_star_step_far_test:
        ld a,(star_frame)
        and 7
        ret nz
        ld hl,STAR_FAR
        ld a,(star_far)
        call stars_draw
        ld a,(star_far)
        inc a
        cp 24
        jr c,__D_core_28_star_step_far_store
        xor a
__D_core_28_star_step_far_store:
        ld (star_far),a
        ld hl,STAR_FAR
        jp stars_draw

; HL -> x,y pairs; A = horizontal phase.  Left points move left, right points
; move right, wrapping at the outer edge of each 32-pixel side strip.
; 58 bytes — Plots one star layer while respecting every protected screen rectangle.
stars_draw:
        ld (star_tmp),a
__D_core_29_stars_draw_star:
        ld a,(hl)
        inc hl
        cp 255
        ret z
        ld b,a
        ld c,(hl)
        inc hl
        ; top/bottom HUD rows never participate in the moving field
        ld a,c
        cp 24
        jr c,__D_core_29_stars_draw_star
        cp 168
        jr nc,__D_core_29_stars_draw_star
        push hl
        ld a,b
        and 0x7F
        ld d,a
        ld a,(star_tmp)
        bit 7,b
        jr nz,__D_core_29_stars_draw_right
        ld e,a
        ld a,d
        sub e
        jr nc,__D_core_29_stars_draw_left_ok
        add a,24
__D_core_29_stars_draw_left_ok:
        ld b,a                  ; x = 0..23, safely west of the robot
        jr __D_core_29_stars_draw_plot
__D_core_29_stars_draw_right:
        add a,d
        cp 24
        jr c,__D_core_29_stars_draw_right_ok
        sub 24
__D_core_29_stars_draw_right_ok:
        or 224
        ld b,a                  ; x = 224..247, east stars only
__D_core_29_stars_draw_plot:
        call plot_xor
        pop hl
        jr __D_core_29_stars_draw_star

STAR_FAR:
        db 4,31,19,77,7,143
        db 132,38,147,94,148,150
        ; compact slow galaxy clusters
        db 16,96,14,96,18,96,17,98
        db 135,118,133,118,137,118,136,120
        db 255
STAR_MID:
        db 6,28,9,84,13,130
        db 133,30,136,101,140,144
        ; compact mid-depth galaxy clusters
        db 0,124,22,124,1,126,3,123
        db 147,62,145,62,148,64,150,61
        db 255
STAR_NEAR:
        ; only two short fast streaks on each side
        db 5,36,7,36,10,118,12,118
        db 133,45,135,45,146,158,148,158
        db 255

; erase rectangle from the clean copy: B=tlx C=tly D=bytes wide E=rows
; 43 bytes — Restores a rectangular patch from the clean board backing store.
erase_rect:
        ld a,b
        rrca
        rrca
        rrca
        and 31
        ld (er_col),a
        ld a,d
        ld (er_w),a
        ld b,e
__D_core_33_erase_rect_row:   push bc
        ld h,ROWLO>>8
        ld l,c
        ld a,(hl)
        inc h
        ld d,(hl)
        ld hl,er_col
        add a,(hl)
        ld e,a
        ld hl,BGOFF
        add hl,de
        ld a,(er_w)
        ld c,a
        ld b,0
        ldir
        pop bc
        inc c
        djnz __D_core_33_erase_rect_row
        ret

; masked sprite: B=tlx C=tly A=kind
; 90 bytes — Draws a masked pre-shifted sprite without leaving pixel confetti behind.
draw_sprite:
        push bc
        add a,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,SPRTAB
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (ds_ptr),de
        ld a,(hl)
        ld (ds_w),a
        inc hl
        ld a,(hl)
        ld (ds_h),a
        inc hl
        ld c,(hl)
        pop de
        push de
        ld a,d
        and 7
        ld b,a
        call mul8u
        ld de,(ds_ptr)
        add hl,de
        pop bc
        ld a,b
        rrca
        rrca
        rrca
        and 31
        ld (ds_col),a
        ld a,(ds_h)
        ld b,a
__D_core_34_draw_sprite_row:   push bc
        push hl
        ld h,ROWLO>>8
        ld l,c
        ld a,(hl)
        inc h
        ld d,(hl)
        ld hl,ds_col
        add a,(hl)
        ld e,a
        pop hl
        ld a,(ds_w)
        ld b,a
__D_core_34_draw_sprite_byte:  ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc e
        djnz __D_core_34_draw_sprite_byte
        pop bc
        inc c
        djnz __D_core_34_draw_sprite_row
        ret

SPRTAB:
        dw SPR_WHITE
        db 2,8,32,0,0,0
        dw SPR_BLACK
        db 2,8,32,0,0,0
        dw SPR_QUEEN
        db 2,8,32,0,0,0
        dw SPR_STRIKER
        db 3,10,60,0,0,0

; ---------------------------------------------------------------- text
; 65 bytes total — Prints ordinary text one character at a time, very 1982.

; print 0-terminated string HL at B=row C=col
; 14 bytes — Moves the ROM cursor and feeds a zero-terminated string to the printer.
print_at:
        ld a,(hl)
        or a
        ret z
        push hl
        push bc
        call put_char
        pop bc
        pop hl
        inc hl
        inc c
        jr print_at

; A=char B=row C=col
; 51 bytes — Draws one ordinary character directly into screen pixels.
put_char:
        cp 128
        jr nc,__D_core_37_put_char_udg
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,0x3D00
        jr __D_core_37_put_char_go
__D_core_37_put_char_udg:   sub 128
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,UDG
__D_core_37_put_char_go:    add hl,de
        ex de,hl
        ld a,b
        add a,a
        add a,a
        add a,a
        ld h,ROWLO>>8
        ld l,a
        ld a,(hl)
        inc h
        ld h,(hl)
        add a,c
        ld l,a
        ld b,8
__N_core_1_7:      ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz __N_core_1_7
        ret

; ---------------------------------------------------------------- 64-column text
; 604 bytes total — Squeezes tiny text into half-width cells and keeps the title tidy.
; Glyphs are 4x8 (FONT64, glyph in the high nibble).  Columns are half-cells 0-63.

; HL = screen address of text row B, half-column C; carry set if C is odd
; 19 bytes — Finds the bitmap byte for a half-width text cell, because coordinates were too easy.
cell_addr:
        ld a,b
        add a,a
        add a,a
        add a,a
        ld h,ROWLO>>8
        ld l,a
        ld a,(hl)
        inc h
        ld h,(hl)
        ld l,a
        ld a,c
        srl a
        or l
        ld l,a
        ld a,c
        rrca
        ret

; A = char, B = row, C = half-column.  Chars 128+ are the 8-pixel UDGs (C even).
; 75 bytes — Draws one 4-pixel-wide glyph while sharing a byte with its neighbour.
put64:
        cp 128
        jr nc,__D_core_39_put64_udg
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,FONT64
        add hl,de
        ex de,hl
        call cell_addr
        ld b,8
        jr c,__D_core_39_put64_odd
__D_core_39_put64_ev:    ld a,(de)
        xor (hl)
        and 0xF0
        xor (hl)
        ld (hl),a
        inc de
        inc h
        djnz __D_core_39_put64_ev
        ret
__D_core_39_put64_odd:   ld a,(de)
        rrca
        rrca
        rrca
        rrca
        xor (hl)
        and 0x0F
        xor (hl)
        ld (hl),a
        inc de
        inc h
        djnz __D_core_39_put64_odd
        ret
__D_core_39_put64_udg:   sub 128
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,UDG
        add hl,de
        ex de,hl
        call cell_addr
        ld b,8
__N_core_1_8:      ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz __N_core_1_8
        ret

; print 0-terminated string HL at B = row, C = half-column (a UDG takes two)
; 20 bytes — Prints a zero-terminated half-width string and advances the tiny cursor.
print64:
        ld a,(hl)
        or a
        ret z
        push hl
        push bc
        call put64
        pop bc
        pop hl
        ld a,(hl)
        inc hl
        inc c
        cp 128
        jr c,print64
        inc c
        jr print64

; print string HL centred on the whole of row B, blanking the rest of the row
; 58 bytes — Measures a half-width string and centres it without using a ruler.
center64:
        push hl
        ld c,0
__N_core_1_9:      ld a,(hl)
        or a
        jr z,__N_core_2_4
        inc hl
        inc c
        jr __N_core_1_9
__N_core_2_4:      ld a,64
        sub c
        jr nc,__N_core_3_1
        xor a
__N_core_3_1:      srl a
        ld (c64_pad),a
        pop hl
        ld c,0
__D_core_41_center64_col:   ld a,(c64_pad)
        ld e,a
        ld a,c
        sub e
        ld a,' '
        jr c,__D_core_41_center64_put               ; still in the left margin
        ld a,(hl)
        or a
        jr nz,__N_core_4_0
        ld a,' '                ; past the end: keep HL on the terminator
        jr __D_core_41_center64_put
__N_core_4_0:      inc hl
__D_core_41_center64_put:   push hl
        push bc
        call put64
        pop bc
        pop hl
        inc c
        ld a,c
        cp 64
        jr c,__D_core_41_center64_col
        ret

; five-pixel title face lifted from the reference tape's screen pixels
; 122 bytes — Renders the small title with its hand-tuned glyph substitutions.
draw_title64:
        ; remove the packed picture's original top-line lettering first
        ld c,0
__D_core_42_draw_title64_clr_y:
        push bc
        call row_de
        xor a
        ld b,32
__D_core_42_draw_title64_clr_b:
        ld (de),a
        inc e
        djnz __D_core_42_draw_title64_clr_b
        pop bc
        inc c
        ld a,c
        cp 8
        jr c,__D_core_42_draw_title64_clr_y

        ; 28 characters at a five-pixel advance = 140 pixels, centred at x=58
        ld hl,S_TITLE
        ld a,58
        ld (title_x),a
__D_core_42_draw_title64_next:
        ld a,(hl)
        or a
        ret z
        inc hl
        cp ' '
        jr z,__D_core_42_draw_title64_advance
        push hl
        call title5_find
        push ix
        push hl
        pop ix
        ld c,0
__D_core_42_draw_title64_row:
        ld a,(ix+0)
        ld (title_bits),a
        ld a,(title_x)
        ld b,a
        ld a,(title_bits)
        bit 4,a
        call nz,plot_xor
        inc b
        ld a,(title_bits)
        bit 3,a
        call nz,plot_xor
        inc b
        ld a,(title_bits)
        bit 2,a
        call nz,plot_xor
        inc b
        ld a,(title_bits)
        bit 1,a
        call nz,plot_xor
        inc b
        ld a,(title_bits)
        bit 0,a
        call nz,plot_xor
        inc ix
        inc c
        ld a,c
        cp 8
        jr c,__D_core_42_draw_title64_row
        pop ix
        pop hl
__D_core_42_draw_title64_advance:
        ld a,(title_x)
        add a,5
        ld (title_x),a
        jr __D_core_42_draw_title64_next

; 20 bytes — Looks up one title-specific 5-pixel glyph and admits defeat cleanly.
title5_find:
        ld c,a
        ld hl,TITLE5
        ld b,15
__D_core_43_title5_find_find:
        ld a,(hl)
        inc hl
        cp c
        ret z
        ld de,8
        add hl,de
        djnz __D_core_43_title5_find_find
        ld hl,TITLE5_BLANK
        ret

TITLE5:
        db 'S',0,0,14,16,12,2,28,0
        db 'A',0,0,12,18,30,18,18,0
        db 'N',0,0,18,26,22,18,18,0
        db 'Y',0,0,18,18,12,4,4,0
        db 'L',0,0,16,16,16,16,30,0
        db 'C',0,0,14,16,16,16,14,0
        db 'n',0,0,28,18,18,18,18,0
        db 'e',0,0,12,18,30,16,14,0
        db 't',8,8,28,8,8,10,4,0
        db 'a',0,0,12,2,14,18,14,0
        db 'b',16,16,28,18,18,18,28,0
        db 's',0,0,14,16,12,2,28,0
        db 'r',0,0,22,24,16,16,16,0
        db 'o',0,0,12,18,18,18,12,0
        db 'm',0,0,17,27,21,17,17,0
TITLE5_BLANK:
        db 0,0,0,0,0,0,0,0

; message buffer (status line, row 23, 64 columns, printed centred)
; 15 bytes — Clears the message buffer and puts its cursor back at the beginning.
msg_clear:
        ld hl,msg_buf
        ld b,65
__N_core_1_10:      ld (hl),0
        inc hl
        djnz __N_core_1_10
        xor a
        ld (msg_pos),a
        ret
; append char A
; 27 bytes — Appends one character to the message buffer without overrunning the furniture.
msg_c:
        push hl
        push de
        ld e,a
        ld a,(msg_pos)
        cp 64
        jr nc,__N_core_1_11
        ld hl,msg_buf
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ld (hl),e
        ld hl,msg_pos
        inc (hl)
__N_core_1_11:      pop de
        pop hl
        ret
; append string HL
; 9 bytes — Appends a zero-terminated string to the current status message.
msg_s:
        ld a,(hl)
        or a
        ret z
        call msg_c
        inc hl
        jr msg_s
; append decimal A (0..255)
; 41 bytes — Formats a small decimal number without dragging in a printing library.
msg_n:
        ld c,0          ; printed-a-digit flag
        ld b,100
        call __D_core_49_msg_n_dig
        ld b,10
        call __D_core_49_msg_n_dig
        add a,'0'
        jp msg_c
__D_core_49_msg_n_dig:   ld d,'0'-1
__N_core_1_12:      inc d
        sub b
        jr nc,__N_core_1_12
        add a,b
        ld e,a
        ld a,d
        cp '0'
        jr nz,__N_core_2_5
        bit 0,c
        jr z,__N_core_3_2
__N_core_2_5:      call msg_c
        ld c,1
__N_core_3_2:      ld a,e
        ret
; 12 bytes — Paints the assembled status message on its protected screen line.
msg_show:
        xor a
        ld (note_t),a           ; a real message replaces any sound-mode notice
        ld hl,msg_buf
        ld b,23
        jp center64

; mover label "RED-N"
; 27 bytes — Finds which logical player is sitting in the physical seat whose turn it is.
msg_mover:
        call mover_pair
        call msg_pair
        ld a,'-'
        call msg_c
        ld a,(seat)
        ld hl,SEATCH
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ld a,(hl)
        jp msg_c
; pair name for pair A
; 12 bytes — Prints the side colour after the mapping rules have had their say.
msg_pair:
        ld hl,S_RED
        or a
        jr z,__N_core_1_13
        ld hl,S_BLU
__N_core_1_13:      jp msg_s

SEATCH: db "NESW"

; ---------------------------------------------------------------- rendering of the pieces
; 397 bytes total — Erases and redraws the pieces before anyone notices the trick.

; 140 bytes — Erases old bodies, redraws live ones, and keeps the board from becoming archaeology.
render:
        xor a
        ld (r_any),a
        ld ix,BODIES
        ld b,NB
__D_core_54_render_p1:    push bc
        ld a,(ix+BF)
        and F_ON
        jr z,__D_core_54_render_off
        ld a,(ix+BX+1)
        sub (ix+BR)
        ld c,a
        ld a,(ix+BY+1)
        sub (ix+BR)
        ld e,a
        ld a,(ix+BDRAWN)
        or a
        jr z,__D_core_54_render_need
        ld a,c
        cp (ix+BTX)
        jr nz,__D_core_54_render_er
        ld a,e
        cp (ix+BTY)
        jr z,__D_core_54_render_nx
__D_core_54_render_er:    call erase_body
__D_core_54_render_need:  ld a,1
        ld (r_any),a
        jr __D_core_54_render_nx
__D_core_54_render_off:   ld a,(ix+BDRAWN)
        or a
        jr z,__D_core_54_render_nx
        call erase_body
        ld a,1
        ld (r_any),a
__D_core_54_render_nx:    ld de,BSZ
        add ix,de
        pop bc
        djnz __D_core_54_render_p1
        ld a,(r_any)
        or a
        ret z
        ld ix,BODIES
        ld b,NB
__D_core_54_render_p2:    push bc
        ld a,(ix+BF)
        and F_ON
        jr z,__D_core_54_render_n2
        ld a,(ix+BX+1)
        sub (ix+BR)
        ld (ix+BTX),a
        ld b,a
        ld a,(ix+BY+1)
        sub (ix+BR)
        ld (ix+BTY),a
        ld c,a
        ld (ix+BDRAWN),1
        ld a,(ix+BK)
        call draw_fast
__D_core_54_render_n2:    ld de,BSZ
        add ix,de
        pop bc
        djnz __D_core_54_render_p2
        ret

; 103 bytes — Restores the old footprint of one body from the clean backing pixels.
erase_body:
        ld (ix+BDRAWN),0
        ld b,(ix+BTX)
        ld c,(ix+BTY)
        ld a,(ix+BK)
        ; DE = screen address of the top-left byte
        push af
        ld h,ROWLO>>8
        ld l,c
        ld a,b
        rrca
        rrca
        rrca
        and 31
        add a,(hl)
        ld e,a
        inc h
        ld d,(hl)
        pop af
        cp 3
        jr z,__D_core_55_erase_body_str
        ld b,8
__D_core_55_erase_body_c:     ld a,d
        add a,BGOFF>>8
        ld h,a
        ld l,e
        ld a,(hl)
        ld (de),a
        inc l
        inc e
        ld a,(hl)
        ld (de),a
        dec e
        DOWN_DE
        djnz __D_core_55_erase_body_c
        ret
__D_core_55_erase_body_str:   ld b,10
__D_core_55_erase_body_s:     ld a,d
        add a,BGOFF>>8
        ld h,a
        ld l,e
        ld a,(hl)
        ld (de),a
        inc l
        inc e
        ld a,(hl)
        ld (de),a
        inc l
        inc e
        ld a,(hl)
        ld (de),a
        dec e
        dec e
        DOWN_DE
        djnz __D_core_55_erase_body_s
        ret

; masked sprite, fast path: B=tlx C=tly A=kind
; 146 bytes — Draws one coin or striker using its cached pre-shifted masked sprite.
draw_fast:
        push af
        add a,a
        ld l,a
        ld h,0
        ld de,SPRBASES
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop af
        push af
        cp 3
        ld a,b
        jr z,__D_core_56_draw_fast_sp
        and 7
        rrca
        rrca
        rrca                ; shift*32
        ld l,a
        ld h,0
        jr __D_core_56_draw_fast_sp2
__D_core_56_draw_fast_sp:    and 7               ; shift*60 = shift*64 - shift*4
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        push de
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        or a
        sbc hl,de
        pop de
__D_core_56_draw_fast_sp2:   add hl,de           ; HL = sprite data
        push hl
        ld h,ROWLO>>8
        ld l,c
        ld a,b
        rrca
        rrca
        rrca
        and 31
        add a,(hl)
        ld e,a
        inc h
        ld d,(hl)
        pop hl
        pop af
        cp 3
        jr z,__D_core_56_draw_fast_str
        ld b,8
__D_core_56_draw_fast_c:     ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc e
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        dec e
        DOWN_DE
        djnz __D_core_56_draw_fast_c
        ret
__D_core_56_draw_fast_str:   ld b,10
__D_core_56_draw_fast_s:     ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc e
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc e
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        dec e
        dec e
        DOWN_DE
        djnz __D_core_56_draw_fast_s
        ret

SPRBASES: dw SPR_WHITE,SPR_BLACK,SPR_QUEEN,SPR_STRIKER

; ---------------------------------------------------------------- robots
; 325 bytes total — Draws the four robot seats; no tiny union cards required.

; robot_pos[s] is the centre of each figure along its side; redraw on change
; 114 bytes — Updates all four robot avatars while avoiding unnecessary redraws.
draw_robots:
        ld a,(phase)
        dec a
        cp PH_HOLD
        jr nc,__D_core_58_draw_robots_dr
        ld a,(BODIES+STRIKER*BSZ+BF)
        and F_ON
        jr z,__D_core_58_draw_robots_dr
        ld hl,BODIES+STRIKER*BSZ+BX+1
        ld a,(seat)
        and 1
        jr z,__N_core_1_14
        ld hl,BODIES+STRIKER*BSZ+BY+1
__N_core_1_14:      ld c,(hl)
        ld a,(seat)
        ld e,a
        ld d,0
        ld hl,robot_pos
        add hl,de
        ld (hl),c
__D_core_58_draw_robots_dr:    ld b,0
__D_core_58_draw_robots_lp:    push bc
        ld a,b
        ld e,b
        ld d,0
        ld hl,robot_pos
        add hl,de
        ld c,(hl)
        ld hl,robot_drawn
        add hl,de
        ld a,(hl)
        cp c
        jr z,__D_core_58_draw_robots_nx
        ld (rb_old),a
        ld (hl),c
        ld a,b
        or a
        jr z,__D_core_58_draw_robots_n
        dec a
        jr z,__D_core_58_draw_robots_e
        dec a
        jr z,__D_core_58_draw_robots_s
        ld a,5
        ld hl,ROB_W
        jr __D_core_58_draw_robots_vert
__D_core_58_draw_robots_e:     ld a,26
        ld hl,ROB_E
__D_core_58_draw_robots_vert:  call draw_vrobot
        jr __D_core_58_draw_robots_nx
__D_core_58_draw_robots_n:     ld a,8
        ld hl,ROB_N
        jr __D_core_58_draw_robots_hor
__D_core_58_draw_robots_s:     ld a,176
        ld hl,ROB_S
__D_core_58_draw_robots_hor:   call draw_hrobot
__D_core_58_draw_robots_nx:    pop bc
        inc b
        ld a,b
        cp 4
        jr c,__D_core_58_draw_robots_lp
        ret

; horizontal robot (16x8): A = top row y, HL = sprite, C = centre x
; 116 bytes — Draws a horizontal robot seat with enough limbs to suggest confidence.
draw_hrobot:
        ld (rb_y),a
        ld (rb_spr),hl
        ld a,c
        cp 64
        jr nc,__N_core_1_15
        ld a,64
__N_core_1_15:      cp 192
        jr c,__N_core_2_6
        ld a,191
__N_core_2_6:      sub 8
        ld (rb_x),a
        ; clear strip cols 6..25
        ld a,(rb_y)
        ld c,a
        ld b,8
__D_core_59_draw_hrobot_clr:   push bc
        call row_de
        ld a,e
        add a,6
        ld l,a
        ld h,d
        ld b,20
__N_core_3_3:      ld (hl),0
        inc l
        djnz __N_core_3_3
        pop bc
        inc c
        djnz __D_core_59_draw_hrobot_clr
        ; draw
        ld a,(rb_y)
        ld c,a
        ld hl,(rb_spr)
        ld b,8
__D_core_59_draw_hrobot_row:   push bc
        push hl
        call row_de
        ld a,(rb_x)
        rrca
        rrca
        rrca
        and 31
        add a,e
        ld e,a
        pop hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        push hl
        ld l,0
        ld a,(rb_x)
        and 7
        jr z,__N_core_5_0
__N_core_4_1:      srl b
        rr c
        rr l
        dec a
        jr nz,__N_core_4_1
__N_core_5_0:      ex de,hl
        ld a,(hl)
        or b
        ld (hl),a
        inc l
        ld a,(hl)
        or c
        ld (hl),a
        inc l
        ld a,(hl)
        or e
        ld (hl),a
        pop hl
        pop bc
        inc c
        djnz __D_core_59_draw_hrobot_row
        ret

; vertical robot (8x16): A = byte column, HL = sprite, C = centre y
; 95 bytes — Draws a vertical robot seat, rotated without rotating the whole universe.
draw_vrobot:
        ld (rb_x),a
        ld (rb_spr),hl
        ld a,c
        cp 32
        jr nc,__N_core_1_16
        ld a,32
__N_core_1_16:      cp 160
        jr c,__N_core_2_7
        ld a,159
__N_core_2_7:      sub 8
        ld (rb_y),a
        ld c,24
        ld b,144
        ld a,(rb_old)
        cp 0xFF
        jr z,__D_core_60_draw_vrobot_clr
        cp 32
        jr nc,__N_core_6_0
        ld a,32
__N_core_6_0:      cp 160
        jr c,__N_core_7_0
        ld a,159
__N_core_7_0:      sub 8
        ld c,a
        ld b,16
__D_core_60_draw_vrobot_clr:   push bc
        call row_de
        ld a,(rb_x)
        add a,e
        ld e,a
        xor a
        ld (de),a
        pop bc
        inc c
        djnz __D_core_60_draw_vrobot_clr
        ld a,(rb_y)
        ld c,a
        ld hl,(rb_spr)
        ld b,16
__D_core_60_draw_vrobot_row:   push bc
        push hl
        call row_de
        ld a,(rb_x)
        add a,e
        ld e,a
        pop hl
        ld a,(hl)
        ld (de),a
        inc hl
        pop bc
        inc c
        djnz __D_core_60_draw_vrobot_row
        ret

; ---------------------------------------------------------------- sound effects
; 160 bytes total — Makes short beeps and thumps while leaving the game state alone.
; Short 1-bit effects built around the same phase-accumulator technique used by
; utz nanobeep (tuklusan/ZX-Spectrum-1-Bit-Routines) with noise accents in the
; spirit of the repository's later FX engines.  Border stays black: port $FE
; output only drives the beeper bits.  sfx_busy mutes the live groove briefly.

; 20 bytes — Honours sound mode, marks the effect busy, and calls the requested chirp.
sfx_run:
        ld a,(mute)
        or a
        ret nz
        ld a,1
        ld (sfx_busy),a
        call jp_hl
        xor a
        ld (sfx_busy),a
        out (0xFE),a
        ret
; 1 byte — Jumps through HL; one byte, no committee, no return ticket.
jp_hl:  jp (hl)

; 5 bytes — Selects the metallic coin-click recipe.
snd_click:
        ld hl,snd_click_b
        jr sfx_run
; 5 bytes — Selects the cushion-thud recipe.
snd_thud:
        ld hl,snd_thud_b
        jr sfx_run
; 5 bytes — Selects the pocket-drop recipe.
snd_pocket:
        ld hl,snd_pocket_b
        jr sfx_run
; 5 bytes — Selects the striker-flick recipe.
snd_flick:
        ld hl,snd_flick_b
        jr sfx_run

; E nudges phase, C counts cycles.  The pulse-making trick comes from nanobeep.
; 22 bytes — Emits a short phase-accumulator burst while leaving game state untouched.
sfx_phase_burst:
        xor a
        ld d,a
__D_core_67_sfx_phase_burst_pb:    ld a,d
        add a,e
        ld d,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
        ld b,18
__D_core_67_sfx_phase_burst_pd:    djnz __D_core_67_sfx_phase_burst_pd
        dec c
        jr nz,__D_core_67_sfx_phase_burst_pb
        xor a
        out (0xFE),a
        ret

; coin on coin: two high, metallic phase bursts
; 18 bytes — Builds the two bright bursts that make coin-on-coin sound less imaginary.
snd_click_b:
        ld e,104
        ld c,22
        call sfx_phase_burst
        ld b,28
__D_core_68_snd_click_b_cgap:  djnz __D_core_68_snd_click_b_cgap
        ld e,82
        ld c,18
        jp sfx_phase_burst

; cushion: a short descending wooden knock
; 18 bytes — Builds the softer descending burst used for cushion contact.
snd_thud_b:
        ld e,70
__D_core_69_snd_thud_b_th:    ld c,7
        push de
        call sfx_phase_burst
        pop de
        ld a,e
        sub 7
        ld e,a
        cp 21
        jr nc,__D_core_69_snd_thud_b_th
        ret

; pocket: descending plonk followed by a sparse net-rattle noise burst
; 38 bytes — Builds the low pocket thunk with a brief noisy landing.
snd_pocket_b:
        ld e,92
__D_core_70_snd_pocket_b_pk:    ld c,5
        push de
        call sfx_phase_burst
        pop de
        ld a,e
        sub 6
        ld e,a
        cp 28
        jr nc,__D_core_70_snd_pocket_b_pk
        ld e,36
__D_core_70_snd_pocket_b_nr:    call rand
        ld a,l
        and 0x10
        out (0xFE),a
        ld b,24
__D_core_70_snd_pocket_b_nd:    djnz __D_core_70_snd_pocket_b_nd
        dec e
        jr nz,__D_core_70_snd_pocket_b_nr
        xor a
        out (0xFE),a
        ret

; striker flick: opening noise transient, then a tiny bright click
; 23 bytes — Builds the striker flick from a tiny noise snap and bright tail.
snd_flick_b:
        ld e,32
__D_core_71_snd_flick_b_fn:    call rand
        ld a,l
        and 0x10
        out (0xFE),a
        ld b,e
__D_core_71_snd_flick_b_fd:    djnz __D_core_71_snd_flick_b_fd
        dec e
        jr nz,__D_core_71_snd_flick_b_fn
        ld e,116
        ld c,12
        jp sfx_phase_burst

; ---------------------------------------------------------------- physics
; 1862 bytes total — Moves, bounces, pockets, and collides everything that refuses to sit still.
;
; Positions are 8.8 screen pixels; velocities are 1/2048 px per tick.
; Board friction is dry Coulomb sliding: each moving body loses a constant ACC of
; speed per tick along its direction (BS holds |v|, BDX/BDY the per-tick decrement).

; 128 bytes — Runs one physics tick until every active body has moved or confessed it stopped.
phys_tick:
        ; the fastest body decides the number of sub-steps (each moves at most ~1.8 px)
        ld ix,BODIES
        ld b,NB
        ld hl,0
__D_core_72_phys_tick_mx:    ld a,(ix+BF)
        cp F_ON|F_MOV
        jr nz,__N_core_1_17
        ld e,(ix+BS)
        ld d,(ix+BS+1)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,__N_core_1_17
        ex de,hl
__N_core_1_17:      ld de,BSZ
        add ix,de
        djnz __D_core_72_phys_tick_mx
        ld bc,0x0103
        ld de,4096
        or a
        sbc hl,de
        jr c,__N_core_2_8
        ld bc,0x0204
__N_core_2_8:      ld a,c
        ld (sub_shift),a
__D_core_72_phys_tick_sub:   push bc
        ld ix,BODIES
        ld b,NB
__D_core_72_phys_tick_s:     push bc
        ld a,(ix+BF)
        cp F_ON|F_MOV
        call z,body_move
        ld de,BSZ
        add ix,de
        pop bc
        djnz __D_core_72_phys_tick_s
        call collisions
        pop bc
        djnz __D_core_72_phys_tick_sub
        ld ix,BODIES
        ld b,NB
__D_core_72_phys_tick_f:     push bc
        ld a,(ix+BF)
        cp F_ON|F_MOV
        call z,body_friction
        ld de,BSZ
        add ix,de
        pop bc
        djnz __D_core_72_phys_tick_f
        ld hl,BODIES+BF
        ld de,BSZ
        ld b,NB
        xor a
__N_core_3_4:      ld c,(hl)
        or c
        add hl,de
        djnz __N_core_3_4
        and F_MOV
        ld (any_moving),a
        ret

; 65 bytes — Integrates one body's 8.8 position from its current velocity.
body_move:
        ld a,(sub_shift)
        ld b,a
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
__N_core_1_18:      sra h
        rr l
        djnz __N_core_1_18
        ld e,(ix+BX)
        ld d,(ix+BX+1)
        add hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        ld a,(sub_shift)
        ld b,a
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
__N_core_2_9:      sra h
        rr l
        djnz __N_core_2_9
        ld e,(ix+BY)
        ld d,(ix+BY+1)
        add hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        call pocket_check
        ret c
        jp walls

; 68 bytes — Applies board friction and stops velocities that have run out of enthusiasm.
body_friction:
        ld l,(ix+BS)
        ld h,(ix+BS+1)
        ld de,ACC
        or a
        sbc hl,de
        jr c,body_stop
        ld (ix+BS),l
        ld (ix+BS+1),h
        or a
        sbc hl,de
        jr c,body_stop
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
        ld e,(ix+BDX)
        ld d,(ix+BDX+1)
        or a
        sbc hl,de
        ld (ix+BVX),l
        ld (ix+BVX+1),h
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
        ld e,(ix+BDY)
        ld d,(ix+BDY+1)
        or a
        sbc hl,de
        ld (ix+BVY),l
        ld (ix+BVY+1),h
        ret

; 24 bytes — Zeros one body's velocity and clears its moving flag.
body_stop:
        xor a
        ld (ix+BVX),a
        ld (ix+BVX+1),a
        ld (ix+BVY),a
        ld (ix+BVY+1),a
        ld (ix+BS),a
        ld (ix+BS+1),a
        res 1,(ix+BF)
        ret

; carry set if the body dropped into a pocket
; 130 bytes — Tests pocket geometry and records newly swallowed bodies for the resolver.
pocket_check:
        ld a,(ix+BX+1)
        ld c,60
        ld d,0
        cp 68
        jr c,__D_core_76_pocket_check_xok
        ld c,196
        ld d,1
        cp 189
        jr nc,__D_core_76_pocket_check_xok
        or a
        ret
__D_core_76_pocket_check_xok:   sub c
        ld (pk_dx),a
        ld a,(ix+BY+1)
        ld c,28
        cp 36
        jr c,__D_core_76_pocket_check_yok
        ld c,164
        set 1,d
        cp 157
        jr nc,__D_core_76_pocket_check_yok
        or a
        ret
__D_core_76_pocket_check_yok:   sub c
        ld (pk_dy),a
        ld a,d
        ld (pk_idx),a
        ld a,(pk_dx)
        or a
        jp p,__N_core_1_19
        neg
__N_core_1_19:      ld b,a
        ld c,a
        call mul8u
        push hl
        ld a,(pk_dy)
        or a
        jp p,__N_core_2_10
        neg
__N_core_2_10:      ld b,a
        ld c,a
        call mul8u
        pop de
        add hl,de
        ld de,49
        or a
        sbc hl,de
        ret nc                ; distance >= 7: still on the board
        ; into the pocket
        call body_stop
        ld (ix+BF),0
        ld a,(pk_idx)
        ld (ix+BPK),a
        ld a,(pk_count)
        cp 20
        jr nc,__N_core_3_5
        ld e,a
        ld d,0
        ld hl,pk_ids
        add hl,de
        ld a,(ix+BID)
        ld (hl),a
        ld hl,pk_count
        inc (hl)
__N_core_3_5:      call snd_pocket
        scf
        ret

; 177 bytes — Keeps bodies inside the board and bounces them off legal cushion segments.
walls:
        xor a
        ld (w_evt),a
        ; left: lim = (56+r)*256
        ld a,56
        add a,(ix+BR)
        ld h,a
        ld l,0
        ld e,(ix+BX)
        ld d,(ix+BX+1)
        push hl
        or a
        sbc hl,de             ; lim - x
        pop hl
        jr c,__D_core_77_walls_x2
        jr z,__D_core_77_walls_x2
        add hl,hl             ; 2*lim - x
        or a
        sbc hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        bit 7,(ix+BVX+1)
        call nz,bounce_vx
__D_core_77_walls_x2:    ld a,200
        sub (ix+BR)
        ld h,a
        ld l,0
        ld e,(ix+BX)
        ld d,(ix+BX+1)
        ex de,hl
        push de
        or a
        sbc hl,de             ; x - lim
        pop de
        jr c,__D_core_77_walls_y1
        jr z,__D_core_77_walls_y1
        ex de,hl              ; hl = lim, de = over
        or a
        sbc hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        bit 7,(ix+BVX+1)
        call z,bounce_vx
__D_core_77_walls_y1:    ld a,24
        add a,(ix+BR)
        ld h,a
        ld l,0
        ld e,(ix+BY)
        ld d,(ix+BY+1)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,__D_core_77_walls_y2
        jr z,__D_core_77_walls_y2
        add hl,hl
        or a
        sbc hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        bit 7,(ix+BVY+1)
        call nz,bounce_vy
__D_core_77_walls_y2:    ld a,168
        sub (ix+BR)
        ld h,a
        ld l,0
        ld e,(ix+BY)
        ld d,(ix+BY+1)
        ex de,hl
        push de
        or a
        sbc hl,de
        pop de
        jr c,__D_core_77_walls_done
        jr z,__D_core_77_walls_done
        ex de,hl
        or a
        sbc hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        bit 7,(ix+BVY+1)
        call z,bounce_vy
__D_core_77_walls_done:  ld a,(w_evt)
        or a
        ret z
        call snd_thud
        jp recompute

; 21 bytes — Reflects and damps horizontal velocity after a vertical-wall encounter.
bounce_vx:
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
        call damp_neg
        ld (ix+BVX),l
        ld (ix+BVX+1),h
        ld a,1
        ld (w_evt),a
        ret
; 21 bytes — Reflects and damps vertical velocity after a horizontal-wall encounter.
bounce_vy:
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
        call damp_neg
        ld (ix+BVY),l
        ld (ix+BVY+1),h
        ld a,1
        ld (w_evt),a
        ret
; HL = -(0.906 * HL)   (cushion restitution 0.9)
; 31 bytes — Negates and damps a signed velocity component without inventing energy.
damp_neg:
        push bc
        ld b,h
        ld c,l
        sra b
        rr c
        sra b
        rr c
        sra b
        rr c
        or a
        sbc hl,bc
        sra b
        rr c
        sra b
        rr c
        add hl,bc
        pop bc
        jp neghl

; keep a body inside the cushions without touching its velocity
; 72 bytes — Clamps a body back inside legal bounds after numerical enthusiasm.
clamp_body:
        ld a,56
        add a,(ix+BR)
        cp (ix+BX+1)
        jr c,__N_core_1_20
        jr z,__N_core_1_20
        ld (ix+BX+1),a
        ld (ix+BX),0
__N_core_1_20:      ld a,199
        sub (ix+BR)
        cp (ix+BX+1)
        jr nc,__N_core_2_11
        ld (ix+BX+1),a
        ld (ix+BX),255
__N_core_2_11:      ld a,24
        add a,(ix+BR)
        cp (ix+BY+1)
        jr c,__N_core_3_6
        jr z,__N_core_3_6
        ld (ix+BY+1),a
        ld (ix+BY),0
__N_core_3_6:      ld a,167
        sub (ix+BR)
        cp (ix+BY+1)
        ret nc
        ld (ix+BY+1),a
        ld (ix+BY),255
        ret

; recompute |v| and the per-tick friction decrement after a velocity change.
; |v| ~ max(M, 7/8 M + 1/2 m) (within ~3%); the decrement keeps the exact direction.
; 143 bytes — Rebuilds collision distance and relative-motion terms from current body state.
recompute:
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
        call abshl
        ld (rc_ax),hl
        ld e,l
        ld d,h
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
        call abshl
        ld (rc_ay),hl
        ; HL = ay, DE = ax -> HL = max, DE = min
        or a
        sbc hl,de
        add hl,de
        jr nc,__N_core_1_21
        ex de,hl
__N_core_1_21:      ld b,h
        ld c,l              ; BC = max
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                ; max/8
        push hl
        ld h,b
        ld l,c
        pop de
        or a
        sbc hl,de           ; 7/8 max
        ex de,hl
        ld hl,(rc_ay)
        ; min = (ax+ay) - max
        push de
        ld de,(rc_ax)
        add hl,de
        or a
        sbc hl,bc
        srl h
        rr l                ; min/2
        pop de
        add hl,de           ; 7/8 max + min/2
        or a
        sbc hl,bc
        add hl,bc
        jr nc,__N_core_2_12
        ld h,b
        ld l,c
__N_core_2_12:      ld de,ACC*2
        or a
        sbc hl,de
        jp c,body_stop
        add hl,de
        ld (ix+BS),l
        ld (ix+BS+1),h
        ld (rc_s),hl
        set 1,(ix+BF)
        ld hl,(rc_ax)
        call fric_comp
        bit 7,(ix+BVX+1)
        call nz,neghl
        ld (ix+BDX),l
        ld (ix+BDX+1),h
        ld hl,(rc_ay)
        call fric_comp
        bit 7,(ix+BVY+1)
        call nz,neghl
        ld (ix+BDY),l
        ld (ix+BDY+1),h
        ret

; HL = ACC * HL / rc_s for 0 <= HL <= rc_s, via q = 128*HL/s
; 40 bytes — Computes the friction compensation term used by the collision solver.
fric_comp:
        ld bc,(rc_s)
        xor a
        sbc hl,bc
        jr nc,__N_core_1_22
        add hl,bc
        jr __N_core_2_13
__N_core_1_22:      inc a
__N_core_2_13:      ld e,7
__N_core_3_7:      add hl,hl
        rla
        or a
        sbc hl,bc
        jr nc,__N_core_4_2
        add hl,bc
        jr __N_core_5_1
__N_core_4_2:      inc a
__N_core_5_1:      dec e
        jr nz,__N_core_3_7
        ld b,a
        ld c,ACC
        call mul8u
        add hl,hl
        ld l,h
        ld h,0
        ret

; sweep and prune: on-board bodies kept sorted by x; only neighbours within 11 px are tested.
; ord_x / ord_y / ord_id are three consecutive 20-byte arrays.
; 245 bytes — Walks every body pair and resolves contacts that actually overlap.
collisions:
        ; gather all 20 bodies in last sub-step's order (a permutation in ord_id)
        ld hl,ord_id
        ld de,ord_x
        ld b,NB
__D_core_84_collisions_g:     push bc
        push hl
        ld a,(hl)
        push de
        call body_ix
        pop de
        ld a,(ix+BX+1)
        ld (de),a
        ld hl,20
        add hl,de
        ld a,(ix+BY+1)
        ld (hl),a
        ld bc,40
        add hl,bc
        ld a,(ix+BF)
        ld (hl),a
        inc de
        pop hl
        inc hl
        pop bc
        djnz __D_core_84_collisions_g
        ld a,NB
        ld (ord_n),a
        ; insertion sort by x (nearly sorted from the last sub-step)
        ld b,1
__D_core_84_collisions_is:    ld a,(ord_n)
        cp b
        jr z,__D_core_84_collisions_sorted
        ld a,b
        ld (sw_k),a
        ld e,b
        ld d,0
        ld hl,ord_x
        add hl,de
__D_core_84_collisions_isl:   ld a,(hl)
        dec hl
        cp (hl)
        jr nc,__D_core_84_collisions_isn
        ld c,(hl)
        ld (hl),a
        inc hl
        ld (hl),c
        ld de,20
        add hl,de
        ld a,(hl)
        dec hl
        ld c,(hl)
        ld (hl),a
        inc hl
        ld (hl),c
        add hl,de
        ld a,(hl)
        dec hl
        ld c,(hl)
        ld (hl),a
        inc hl
        ld (hl),c
        add hl,de
        ld a,(hl)
        dec hl
        ld c,(hl)
        ld (hl),a
        inc hl
        ld (hl),c
        ld de,-60
        add hl,de
        dec hl
        ld a,(sw_k)
        dec a
        ld (sw_k),a
        jr nz,__D_core_84_collisions_isl
__D_core_84_collisions_isn:   inc b
        jr __D_core_84_collisions_is
__D_core_84_collisions_sorted:
        ld hl,ord_x
        ld a,(ord_n)
        ld (sw_left),a
__D_core_84_collisions_sa:    ld a,(sw_left)
        dec a
        ret z
        ld (sw_left),a
        ld (sw_cnt),a
        ld c,(hl)               ; x_i
        push hl
        ld de,20
        add hl,de
        ld a,(hl)
        ld (sw_yi),a
        add hl,de
        ld a,(hl)
        ld (sw_idi),a
        add hl,de
        ld a,(hl)
        ld (sw_fi),a
        pop hl
        push hl
__D_core_84_collisions_sb:    inc hl
        ld a,(hl)
        sub c
        cp 12
        jr nc,__D_core_84_collisions_sdone            ; everything further right is out of reach
        push hl
        ld de,60
        add hl,de
        ld a,(sw_fi)
        or (hl)
        and F_MOV               ; one of the pair must be moving
        jr z,__D_core_84_collisions_sbn
        ld de,-40
        add hl,de
        ld a,(sw_yi)
        ld b,a
        ld a,(hl)
        sub b
        add a,11
        cp 23
        jr nc,__D_core_84_collisions_sbn
        ld de,20
        add hl,de
        ld a,(hl)               ; id_j
        push bc
        call body_iy
        ld a,(sw_idi)
        call body_ix
        ld a,(ix+BF)
        or (iy+BF)
        and F_MOV
        jr z,__N_core_1_23
        ld a,(ix+BF)
        and (iy+BF)
        and F_ON
        call nz,pair_test
__N_core_1_23:      pop bc
__D_core_84_collisions_sbn:   pop hl
        ld a,(sw_cnt)
        dec a
        ld (sw_cnt),a
        jr nz,__D_core_84_collisions_sb
__D_core_84_collisions_sdone: pop hl
        inc hl
        jr __D_core_84_collisions_sa

; 16 bytes — Points IY at body A from its compact body index.
body_iy:
        add a,a
        ld l,a
        ld h,0
        ld de,BODYPTR
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        pop iy
        ret

; IX = body A
; 16 bytes — Points IX at body B from its compact body index.
body_ix:
        add a,a
        ld l,a
        ld h,0
        ld de,BODYPTR
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        pop ix
        ret

BODYPTR:
        dw BODIES+0*BSZ,BODIES+1*BSZ,BODIES+2*BSZ,BODIES+3*BSZ,BODIES+4*BSZ
        dw BODIES+5*BSZ,BODIES+6*BSZ,BODIES+7*BSZ,BODIES+8*BSZ,BODIES+9*BSZ
        dw BODIES+10*BSZ,BODIES+11*BSZ,BODIES+12*BSZ,BODIES+13*BSZ,BODIES+14*BSZ
        dw BODIES+15*BSZ,BODIES+16*BSZ,BODIES+17*BSZ,BODIES+18*BSZ,BODIES+19*BSZ

; IX = body i (moving), IY = body j
; 576 bytes — Resolves one two-body collision with fixed-point normals, impulse, and separation.
pair_test:
        ld a,(iy+BX+1)
        sub (ix+BX+1)
        add a,12
        cp 25
        ret nc
        ld a,(iy+BY+1)
        sub (ix+BY+1)
        add a,12
        cp 25
        ret nc
        ld a,(ix+BR)
        add a,(iy+BR)
        add a,a
        add a,a
        add a,a
        add a,a
        ld (pt_r16),a
        ld b,a
        ld c,a
        call mul8u
        ld (pt_r2),hl
        ld l,(iy+BX)
        ld h,(iy+BX+1)
        ld e,(ix+BX)
        ld d,(ix+BX+1)
        or a
        sbc hl,de
        call sra4
        ld (pt_dx),hl
        ld l,(iy+BY)
        ld h,(iy+BY+1)
        ld e,(ix+BY)
        ld d,(ix+BY+1)
        or a
        sbc hl,de
        call sra4
        ld (pt_dy),hl
        ld hl,(pt_dx)
        call abshl
        ld b,l
        ld c,l
        call mul8u
        push hl
        ld hl,(pt_dy)
        call abshl
        ld b,l
        ld c,l
        call mul8u
        pop de
        add hl,de
        ret c
        ld (pt_d2),hl
        ld de,(pt_r2)
        or a
        sbc hl,de
        ret nc
        ; in contact
        ld hl,(pt_d2)
        call isqrt16
        or a
        jr nz,__N_core_1_24
        inc a
        ld hl,16
        ld (pt_dx),hl
        ld hl,0
        ld (pt_dy),hl
__N_core_1_24:      ld (pt_dist),a
        ld hl,(pt_dx)
        call sdiv64
        ld (pt_nx),a
        ld hl,(pt_dy)
        call sdiv64
        ld (pt_ny),a
        ; approach speed along the normal: vrel = ((vi-vj).n)/64
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
        ld e,(iy+BVX)
        ld d,(iy+BVX+1)
        or a
        sbc hl,de
        ld a,(pt_nx)
        call smul16x8
        ld (pt_t),hl
        ld (pt_t+2),a
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
        ld e,(iy+BVY)
        ld d,(iy+BVY+1)
        or a
        sbc hl,de
        ld a,(pt_ny)
        call smul16x8
        ld de,(pt_t)
        add hl,de
        ld c,a
        ld a,(pt_t+2)
        adc a,c
        ld b,6
        call sra24
        bit 7,a
        jp nz,__D_core_88_pair_test_corr
        ld a,h
        or l
        jp z,__D_core_88_pair_test_corr
        ld (pt_vrel),hl
        ; impulse factors (1+e)*m_other/(m_i+m_j) in 1/128, e = 0.95, mass ~ r^2
        ld bc,125*256+125
        ld a,(ix+BK)
        cp 3
        jr nz,__N_core_2_14
        ld bc,97*256+152
        jr __N_core_3_8
__N_core_2_14:      ld a,(iy+BK)
        cp 3
        jr nz,__N_core_3_8
        ld bc,152*256+97
__N_core_3_8:      ld a,c
        ld (pt_fj),a
        ld a,b
        ld hl,(pt_vrel)
        call mul16x8u
        ld b,7
        call sra24
        ld (pt_ji),hl
        ld a,(pt_fj)
        ld hl,(pt_vrel)
        call mul16x8u
        ld b,7
        call sra24
        ld (pt_jj),hl
        ; vi -= Ji n ; vj += Jj n
        ld hl,(pt_ji)
        ld a,(pt_nx)
        call smul16x8
        ld b,6
        call sra24
        ex de,hl
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
        or a
        sbc hl,de
        ld (ix+BVX),l
        ld (ix+BVX+1),h
        ld hl,(pt_ji)
        ld a,(pt_ny)
        call smul16x8
        ld b,6
        call sra24
        ex de,hl
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
        or a
        sbc hl,de
        ld (ix+BVY),l
        ld (ix+BVY+1),h
        ld hl,(pt_jj)
        ld a,(pt_nx)
        call smul16x8
        ld b,6
        call sra24
        ex de,hl
        ld l,(iy+BVX)
        ld h,(iy+BVX+1)
        add hl,de
        ld (iy+BVX),l
        ld (iy+BVX+1),h
        ld hl,(pt_jj)
        ld a,(pt_ny)
        call smul16x8
        ld b,6
        call sra24
        ex de,hl
        ld l,(iy+BVY)
        ld h,(iy+BVY+1)
        add hl,de
        ld (iy+BVY),l
        ld (iy+BVY+1),h
        call recompute
        push ix
        push iy
        pop ix
        call recompute
        pop ix
        ld a,(ix+BK)
        cp 3
        jr z,__N_core_4_3
        ld a,(iy+BK)
        cp 3
        jr nz,__N_core_5_2
__N_core_4_3:      ld a,1
        ld (touched),a
__N_core_5_2:      call snd_click
__D_core_88_pair_test_corr:  ; push the pair apart along the normal
        ld a,(pt_dist)
        ld b,a
        ld a,(pt_r16)
        sub b
        srl a
        inc a
        ld (pt_push),a
        ld b,a
        ld a,(pt_nx)
        ld c,a
        call smul8
        sra h
        rr l
        sra h
        rr l
        ex de,hl
        ld l,(ix+BX)
        ld h,(ix+BX+1)
        or a
        sbc hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        ld l,(iy+BX)
        ld h,(iy+BX+1)
        add hl,de
        ld (iy+BX),l
        ld (iy+BX+1),h
        ld a,(pt_push)
        ld b,a
        ld a,(pt_ny)
        ld c,a
        call smul8
        sra h
        rr l
        sra h
        rr l
        ex de,hl
        ld l,(ix+BY)
        ld h,(ix+BY+1)
        or a
        sbc hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        ld l,(iy+BY)
        ld h,(iy+BY+1)
        add hl,de
        ld (iy+BY),l
        ld (iy+BY+1),h
        call clamp_body
        push ix
        push iy
        pop ix
        call clamp_body
        pop ix
        ret

; A = (HL*64)/pt_dist, signed (|HL| <= pt_dist)
; 49 bytes — Divides a signed 16-bit value by 64 with rounding suitable for collision maths.
sdiv64:
        ld a,h
        ld (sd_sign),a
        call abshl
        ld a,(pt_dist)
        ld c,a
        ld b,0
        xor a
        sbc hl,bc
        jr nc,__N_core_1_25
        add hl,bc
        jr __N_core_2_15
__N_core_1_25:      inc a
__N_core_2_15:      ld e,6
__N_core_3_9:      add hl,hl
        rla
        or a
        sbc hl,bc
        jr nc,__N_core_4_4
        add hl,bc
        jr __N_core_5_3
__N_core_4_4:      inc a
__N_core_5_3:      dec e
        jr nz,__N_core_3_9
        ld l,a
        ld a,(sd_sign)
        bit 7,a
        ld a,l
        ret z
        neg
        ret
