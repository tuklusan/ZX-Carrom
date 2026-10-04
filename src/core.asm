; Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
; Licensed under the SANYALnet Labs Non-Commercial License.

; Carrom Arena ZX - core: maths, screen, rendering, physics.

; next pixel row down for DE (screen address)
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
; 446 bytes — Does the sums so the coins can pretend Newton is watching.

; HL = -HL (preserves BC, DE)
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
abshl:
        bit 7,h
        ret z
        jr neghl

; HL >>= 4 (arithmetic)
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
sra24:
        sra a
        rr h
        rr l
        djnz sra24
        ret

; A:HL = -A:HL
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
mul8u:
        ld a,b
        sub c
        jr nc,1F
        neg
1:      ld l,a
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
smul8:
        ld a,b
        xor c
        ld (m8_sign),a
        ld a,b
        or a
        jp p,1F
        neg
        ld b,a
1:      ld a,c
        or a
        jp p,2F
        neg
        ld c,a
2:      call mul8u
        ld a,(m8_sign)
        or a
        ret p
        jp neghl

; A:HL = HL * A (unsigned 16x8 -> 24). Clobbers BC, DE.
mul16x8u:
        ex de,hl
        ld hl,0
        ld c,0
        ld b,8
1:      add hl,hl
        rl c
        rla
        jr nc,2F
        add hl,de
        jr nc,2F
        inc c
2:      djnz 1B
        ld a,c
        ret

; A:HL = HL * A (signed). Clobbers BC, DE.
smul16x8:
        ld b,a
        xor h
        ld (m16_sign),a
        bit 7,h
        call nz,neghl
        ld a,b
        or a
        jp p,1F
        neg
1:      call mul16x8q
        ld b,a
        ld a,(m16_sign)
        or a
        ld a,b
        ret p
        jp neg24
; A:HL = HL * A unsigned, as (H*A)<<8 + L*A with two table multiplies
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
mul16u:
        ld hl,0
        ld a,16
1:      add hl,hl
        rl e
        rl d
        jr nc,2F
        add hl,bc
        jr nc,2F
        inc de
2:      dec a
        jr nz,1B
        ret

; HL = DEHL / BC (unsigned, quotient must fit 16 bits)
div32_16:
        ld a,16
.lp:    add hl,hl
        ex de,hl
        adc hl,hl
        jr c,.over
        sbc hl,bc
        jr nc,.ok
        add hl,bc
        ex de,hl
        jr .next
.over:  or a
        sbc hl,bc
.ok:    ex de,hl
        inc l
.next:  dec a
        jr nz,.lp
        ret

; HL = HL / C (unsigned 16/8), A = remainder. Clobbers B.
div16_8:
        xor a
        ld b,16
1:      add hl,hl
        rla
        jr c,2F
        cp c
        jr c,3F
2:      sub c
        inc l
3:      djnz 1B
        ret

; HL = floor(sqrt(DEHL))
isqrt32:
        ld (sq_n),hl
        ld (sq_n+2),de
        ld b,16
        jr isqrt_core
; A = L = floor(sqrt(HL))  (register digit-by-digit, ~900 T)
isqrt16:
        ld b,8
        ld c,0
        ld de,0
.lp:    add hl,hl
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
        jr c,.no
        inc c
        ex de,hl
        jr .nx
.no:    add hl,de
        ex de,hl
.nx:    pop hl
        djnz .lp
        ld a,c
        ld l,c
        ld h,0
        ret
isqrt_core:
        ld hl,0
        ld (sq_root),hl
        ld (sq_rem),hl
        xor a
        ld (sq_rem+2),a
.lp:    push bc
        ld c,2
.sh:    ld hl,(sq_n)
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
        jr nz,.sh
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
        jr c,.no
        ld (sq_rem),hl
        ld (sq_rem+2),a
        ld hl,(sq_root)
        inc hl
        ld (sq_root),hl
.no:    pop bc
        djnz .lp
        ld hl,(sq_root)
        ret

; HL = random (xorshift16). Preserves BC, DE.
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
rand_n:
        ld hl,128
        call div16_8             ; A = 128 mod C
        ld b,a                   ; size of the rejected tail
.retry: call rand
        ld a,l
        and 127
        add a,b
        jp m,.retry              ; source >= 128-tail: draw again
        sub b                    ; restore the accepted source value
.reduce:
        cp c
        ret c
        sub c
        jr .reduce

; ---------------------------------------------------------------- screen
; 93 bytes — Finds screen rows, restores the board, and flips individual pixels.

; DE = screen address of pixel row C, byte column 0
row_de:
        ld h,ROWLO>>8
        ld l,c
        ld e,(hl)
        inc h
        ld d,(hl)
        ret

draw_board:
        ld hl,BGBUF             ; pixels then attributes from the clean board buffer
        ld de,0x4000
        ld bc,6912
        ldir
        jp draw_title64

; restore just the board pixels (wipes every piece) and forget what was drawn
reset_board_pixels:
        ld hl,BGBUF
        ld de,0x4000
        ld bc,6144
        ldir
        call draw_title64
        call star_redraw
        ld ix,BODIES
        ld b,NB
1:      ld (ix+BDRAWN),0
        ld de,BSZ
        add ix,de
        djnz 1B
        ret

; XOR-plot pixel (B=x, C=y)
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
        add a,BITMASK&255
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
; 555 bytes — Moves the starfield and draws masked sprites without denting the furniture.
; Outer side strips stream away from the board.  Near/mid/far layers move at
; different frame rates.  Clustered points in the far and mid sets form tiny
; spiral-like galaxies that travel with their layer.

star_prepare:
        ; remove the old fixed margin dots from the clean board copy
        ld c,24
.prep_row:
        push bc
        call row_de
        ld a,d
        add a,BGOFF>>8
        ld d,a
        xor a
        ld b,5
.prep_l:
        ld (de),a
        inc e
        djnz .prep_l
        ld a,e
        add a,22
        ld e,a
        xor a
        ld b,5
.prep_r:
        ld (de),a
        inc e
        djnz .prep_r
        pop bc
        inc c
        ld a,c
        cp 168
        jr c,.prep_row

        ; the old picture used light paper here.  The moving stars XOR
        ; pixels in columns 28..30, so make their whole lane black-backed.
        ; Column 31 is the ribbon lane and is black except for its four blocks.
        ld hl,BGBUF+6144+3*32+28
        ld b,18
.attr_row:
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
        djnz .attr_row

        ; four 4x8 colour blocks at the far-right screen edge
        ld c,80
        ld b,32
.ribbon_px:
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
        djnz .ribbon_px
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

star_reset:
        xor a
        ld (star_far),a
        ld (star_mid),a
        ld (star_near),a
        ld a,(frames)
        ld (star_frame),a
        jr star_redraw

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
        jr nz,.far_test
        ld hl,STAR_NEAR
        ld a,(star_near)
        call stars_draw
        ld a,(star_near)
        inc a
        cp 24
        jr c,.near_store
        xor a
.near_store:
        ld (star_near),a
        ld hl,STAR_NEAR
        call stars_draw

        ld a,(star_frame)
        and 3
        jr nz,.far_test
        ld hl,STAR_MID
        ld a,(star_mid)
        call stars_draw
        ld a,(star_mid)
        inc a
        cp 24
        jr c,.mid_store
        xor a
.mid_store:
        ld (star_mid),a
        ld hl,STAR_MID
        call stars_draw

.far_test:
        ld a,(star_frame)
        and 7
        ret nz
        ld hl,STAR_FAR
        ld a,(star_far)
        call stars_draw
        ld a,(star_far)
        inc a
        cp 24
        jr c,.far_store
        xor a
.far_store:
        ld (star_far),a
        ld hl,STAR_FAR
        jp stars_draw

; HL -> x,y pairs; A = horizontal phase.  Left points move left, right points
; move right, wrapping at the outer edge of each 32-pixel side strip.
stars_draw:
        ld (star_tmp),a
.star:
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
        jr c,.star
        cp 168
        jr nc,.star
        push hl
        ld a,b
        and 0x7F
        ld d,a
        ld a,(star_tmp)
        bit 7,b
        jr nz,.right
        ld e,a
        ld a,d
        sub e
        jr nc,.left_ok
        add a,24
.left_ok:
        ld b,a                  ; x = 0..23, safely west of the robot
        jr .plot
.right:
        add a,d
        cp 24
        jr c,.right_ok
        sub 24
.right_ok:
        or 224
        ld b,a                  ; x = 224..247, east stars only
.plot:
        call plot_xor
        pop hl
        jr .star

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
.row:   push bc
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
        djnz .row
        ret

; masked sprite: B=tlx C=tly A=kind
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
.row:   push bc
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
.byte:  ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc e
        djnz .byte
        pop bc
        inc c
        djnz .row
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
; 65 bytes — Prints ordinary text one character at a time, very 1982.

; print 0-terminated string HL at B=row C=col
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
put_char:
        cp 128
        jr nc,.udg
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,0x3D00
        jr .go
.udg:   sub 128
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,UDG
.go:    add hl,de
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
1:      ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz 1B
        ret

; ---------------------------------------------------------------- 64-column text
; 606 bytes — Squeezes tiny text into half-width cells and keeps the title tidy.
; Glyphs are 4x8 (FONT64, glyph in the high nibble).  Columns are half-cells 0-63.

; HL = screen address of text row B, half-column C; carry set if C is odd
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
put64:
        cp 128
        jr nc,.udg
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
        jr c,.odd
.ev:    ld a,(de)
        xor (hl)
        and 0xF0
        xor (hl)
        ld (hl),a
        inc de
        inc h
        djnz .ev
        ret
.odd:   ld a,(de)
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
        djnz .odd
        ret
.udg:   sub 128
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
1:      ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz 1B
        ret

; print 0-terminated string HL at B = row, C = half-column (a UDG takes two)
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
center64:
        push hl
        ld c,0
1:      ld a,(hl)
        or a
        jr z,2F
        inc hl
        inc c
        jr 1B
2:      ld a,64
        sub c
        jr nc,3F
        xor a
3:      srl a
        ld (c64_pad),a
        pop hl
        ld c,0
.col:   ld a,(c64_pad)
        ld e,a
        ld a,c
        sub e
        ld a,' '
        jr c,.put               ; still in the left margin
        ld a,(hl)
        or a
        jr nz,4F
        ld a,' '                ; past the end: keep HL on the terminator
        jr .put
4:      inc hl
.put:   push hl
        push bc
        call put64
        pop bc
        pop hl
        inc c
        ld a,c
        cp 64
        jr c,.col
        ret

; five-pixel title face sampled from the supplied tape's fixed screen raster
draw_title64:
        ; remove the packed picture's original top-line lettering first
        ld c,0
.clr_y:
        push bc
        call row_de
        xor a
        ld b,32
.clr_b:
        ld (de),a
        inc e
        djnz .clr_b
        pop bc
        inc c
        ld a,c
        cp 8
        jr c,.clr_y

        ; 28 characters at a five-pixel advance = 140 pixels, centred at x=58
        ld hl,S_TITLE
        ld a,58
        ld (title_x),a
.next:
        ld a,(hl)
        or a
        ret z
        inc hl
        cp ' '
        jr z,.advance
        push hl
        call title5_find
        push ix
        push hl
        pop ix
        ld c,0
.row:
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
        jr c,.row
        pop ix
        pop hl
.advance:
        ld a,(title_x)
        add a,5
        ld (title_x),a
        jr .next

title5_find:
        ld c,a
        ld hl,TITLE5
        ld b,15
.find:
        ld a,(hl)
        inc hl
        cp c
        ret z
        ld de,8
        add hl,de
        djnz .find
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
msg_clear:
        ld hl,msg_buf
        ld b,65
1:      ld (hl),0
        inc hl
        djnz 1B
        xor a
        ld (msg_pos),a
        ret
; append char A
msg_c:
        push hl
        push de
        ld e,a
        ld a,(msg_pos)
        cp 64
        jr nc,1F
        ld hl,msg_buf
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ld (hl),e
        ld hl,msg_pos
        inc (hl)
1:      pop de
        pop hl
        ret
; append string HL
msg_s:
        ld a,(hl)
        or a
        ret z
        call msg_c
        inc hl
        jr msg_s
; append decimal A (0..255)
msg_n:
        ld c,0          ; printed-a-digit flag
        ld b,100
        call .dig
        ld b,10
        call .dig
        add a,'0'
        jp msg_c
.dig:   ld d,'0'-1
1:      inc d
        sub b
        jr nc,1B
        add a,b
        ld e,a
        ld a,d
        cp '0'
        jr nz,2F
        bit 0,c
        jr z,3F
2:      call msg_c
        ld c,1
3:      ld a,e
        ret
msg_show:
        xor a
        ld (note_t),a           ; a real message replaces any sound-mode notice
        ld hl,msg_buf
        ld b,23
        jp center64

; mover label "RED-N"
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
msg_pair:
        ld hl,S_RED
        or a
        jr z,1F
        ld hl,S_BLU
1:      jp msg_s

SEATCH: db "NESW"

; ---------------------------------------------------------------- rendering of the pieces
; 397 bytes — Erases and redraws the pieces before anyone notices the trick.

render:
        xor a
        ld (r_any),a
        ld ix,BODIES
        ld b,NB
.p1:    push bc
        ld a,(ix+BF)
        and F_ON
        jr z,.off
        ld a,(ix+BX+1)
        sub (ix+BR)
        ld c,a
        ld a,(ix+BY+1)
        sub (ix+BR)
        ld e,a
        ld a,(ix+BDRAWN)
        or a
        jr z,.need
        ld a,c
        cp (ix+BTX)
        jr nz,.er
        ld a,e
        cp (ix+BTY)
        jr z,.nx
.er:    call erase_body
.need:  ld a,1
        ld (r_any),a
        jr .nx
.off:   ld a,(ix+BDRAWN)
        or a
        jr z,.nx
        call erase_body
        ld a,1
        ld (r_any),a
.nx:    ld de,BSZ
        add ix,de
        pop bc
        djnz .p1
        ld a,(r_any)
        or a
        ret z
        ld ix,BODIES
        ld b,NB
.p2:    push bc
        ld a,(ix+BF)
        and F_ON
        jr z,.n2
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
.n2:    ld de,BSZ
        add ix,de
        pop bc
        djnz .p2
        ret

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
        jr z,.str
        ld b,8
.c:     ld a,d
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
        djnz .c
        ret
.str:   ld b,10
.s:     ld a,d
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
        djnz .s
        ret

; masked sprite, fast path: B=tlx C=tly A=kind
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
        jr z,.sp
        and 7
        rrca
        rrca
        rrca                ; shift*32
        ld l,a
        ld h,0
        jr .sp2
.sp:    and 7               ; shift*60 = shift*64 - shift*4
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
.sp2:   add hl,de           ; HL = sprite data
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
        jr z,.str
        ld b,8
.c:     ld a,(de)
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
        djnz .c
        ret
.str:   ld b,10
.s:     ld a,(de)
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
        djnz .s
        ret

SPRBASES: dw SPR_WHITE,SPR_BLACK,SPR_QUEEN,SPR_STRIKER

; ---------------------------------------------------------------- robots
; 325 bytes — Draws the four robot seats; no tiny union cards required.

; robot_pos[s] is the centre of each figure along its side; redraw on change
draw_robots:
        ld a,(phase)
        dec a
        cp PH_HOLD
        jr nc,.dr
        ld a,(BODIES+STRIKER*BSZ+BF)
        and F_ON
        jr z,.dr
        ld hl,BODIES+STRIKER*BSZ+BX+1
        ld a,(seat)
        and 1
        jr z,1F
        ld hl,BODIES+STRIKER*BSZ+BY+1
1:      ld c,(hl)
        ld a,(seat)
        ld e,a
        ld d,0
        ld hl,robot_pos
        add hl,de
        ld (hl),c
.dr:    ld b,0
.lp:    push bc
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
        jr z,.nx
        ld (rb_old),a
        ld (hl),c
        ld a,b
        or a
        jr z,.n
        dec a
        jr z,.e
        dec a
        jr z,.s
        ld a,5
        ld hl,ROB_W
        jr .vert
.e:     ld a,26
        ld hl,ROB_E
.vert:  call draw_vrobot
        jr .nx
.n:     ld a,8
        ld hl,ROB_N
        jr .hor
.s:     ld a,176
        ld hl,ROB_S
.hor:   call draw_hrobot
.nx:    pop bc
        inc b
        ld a,b
        cp 4
        jr c,.lp
        ret

; horizontal robot (16x8): A = top row y, HL = sprite, C = centre x
draw_hrobot:
        ld (rb_y),a
        ld (rb_spr),hl
        ld a,c
        cp 64
        jr nc,1F
        ld a,64
1:      cp 192
        jr c,2F
        ld a,191
2:      sub 8
        ld (rb_x),a
        ; clear strip cols 6..25
        ld a,(rb_y)
        ld c,a
        ld b,8
.clr:   push bc
        call row_de
        ld a,e
        add a,6
        ld l,a
        ld h,d
        ld b,20
3:      ld (hl),0
        inc l
        djnz 3B
        pop bc
        inc c
        djnz .clr
        ; draw
        ld a,(rb_y)
        ld c,a
        ld hl,(rb_spr)
        ld b,8
.row:   push bc
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
        jr z,5F
4:      srl b
        rr c
        rr l
        dec a
        jr nz,4B
5:      ex de,hl
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
        djnz .row
        ret

; vertical robot (8x16): A = byte column, HL = sprite, C = centre y
draw_vrobot:
        ld (rb_x),a
        ld (rb_spr),hl
        ld a,c
        cp 32
        jr nc,1F
        ld a,32
1:      cp 160
        jr c,2F
        ld a,159
2:      sub 8
        ld (rb_y),a
        ld c,24
        ld b,144
        ld a,(rb_old)
        cp 0xFF
        jr z,.clr
        cp 32
        jr nc,6F
        ld a,32
6:      cp 160
        jr c,7F
        ld a,159
7:      sub 8
        ld c,a
        ld b,16
.clr:   push bc
        call row_de
        ld a,(rb_x)
        add a,e
        ld e,a
        xor a
        ld (de),a
        pop bc
        inc c
        djnz .clr
        ld a,(rb_y)
        ld c,a
        ld hl,(rb_spr)
        ld b,16
.row:   push bc
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
        djnz .row
        ret

; ---------------------------------------------------------------- sound effects
; 160 bytes — Makes short beeps and thumps while leaving the game state alone.
; Short 1-bit effects built around the same phase-accumulator technique used by
; utz nanobeep (tuklusan/ZX-Spectrum-1-Bit-Routines) with noise accents in the
; spirit of the repository's later FX engines.  Border stays black: port $FE
; output only drives the beeper bits.  sfx_busy mutes the live groove briefly.

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
jp_hl:  jp (hl)

snd_click:
        ld hl,snd_click_b
        jr sfx_run
snd_thud:
        ld hl,snd_thud_b
        jr sfx_run
snd_pocket:
        ld hl,snd_pocket_b
        jr sfx_run
snd_flick:
        ld hl,snd_flick_b
        jr sfx_run

; E = phase increment, C = cycles.  Core update/output is adapted from nanobeep.
sfx_phase_burst:
        xor a
        ld d,a
.pb:    ld a,d
        add a,e
        ld d,a
        ld b,48
        sbc a,a
        and b
        out (0xFE),a
        ld b,18
.pd:    djnz .pd
        dec c
        jr nz,.pb
        xor a
        out (0xFE),a
        ret

; coin on coin: two high, metallic phase bursts
snd_click_b:
        ld e,104
        ld c,22
        call sfx_phase_burst
        ld b,28
.cgap:  djnz .cgap
        ld e,82
        ld c,18
        jp sfx_phase_burst

; cushion: a short descending wooden knock
snd_thud_b:
        ld e,70
.th:    ld c,7
        push de
        call sfx_phase_burst
        pop de
        ld a,e
        sub 7
        ld e,a
        cp 21
        jr nc,.th
        ret

; pocket: descending plonk followed by a sparse net-rattle noise burst
snd_pocket_b:
        ld e,92
.pk:    ld c,5
        push de
        call sfx_phase_burst
        pop de
        ld a,e
        sub 6
        ld e,a
        cp 28
        jr nc,.pk
        ld e,36
.nr:    call rand
        ld a,l
        and 0x10
        out (0xFE),a
        ld b,24
.nd:    djnz .nd
        dec e
        jr nz,.nr
        xor a
        out (0xFE),a
        ret

; striker flick: opening noise transient, then a tiny bright click
snd_flick_b:
        ld e,32
.fn:    call rand
        ld a,l
        and 0x10
        out (0xFE),a
        ld b,e
.fd:    djnz .fd
        dec e
        jr nz,.fn
        ld e,116
        ld c,12
        jp sfx_phase_burst

; ---------------------------------------------------------------- physics
; 1868 bytes — Moves, bounces, pockets, and collides everything that refuses to sit still.
;
; Positions are 8.8 screen pixels; velocities are 1/2048 px per tick.
; Board friction is dry Coulomb sliding: each moving body loses a constant ACC of
; speed per tick along its direction (BS holds |v|, BDX/BDY the per-tick decrement).

phys_tick:
        ; the fastest body decides the number of sub-steps (each moves at most ~1.8 px)
        ld ix,BODIES
        ld b,NB
        ld hl,0
.mx:    ld a,(ix+BF)
        cp F_ON|F_MOV
        jr nz,1F
        ld e,(ix+BS)
        ld d,(ix+BS+1)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,1F
        ex de,hl
1:      ld de,BSZ
        add ix,de
        djnz .mx
        ld bc,0x0103
        ld de,4096
        or a
        sbc hl,de
        jr c,2F
        ld bc,0x0204
2:      ld a,c
        ld (sub_shift),a
.sub:   push bc
        ld ix,BODIES
        ld b,NB
.s:     push bc
        ld a,(ix+BF)
        cp F_ON|F_MOV
        call z,body_move
        ld de,BSZ
        add ix,de
        pop bc
        djnz .s
        call collisions
        pop bc
        djnz .sub
        ld ix,BODIES
        ld b,NB
.f:     push bc
        ld a,(ix+BF)
        cp F_ON|F_MOV
        call z,body_friction
        ld de,BSZ
        add ix,de
        pop bc
        djnz .f
        ld hl,BODIES+BF
        ld de,BSZ
        ld b,NB
        xor a
3:      ld c,(hl)
        or c
        add hl,de
        djnz 3B
        and F_MOV
        ld (any_moving),a
        ret

body_move:
        ld a,(sub_shift)
        ld b,a
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
1:      sra h
        rr l
        djnz 1B
        ld e,(ix+BX)
        ld d,(ix+BX+1)
        add hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        ld a,(sub_shift)
        ld b,a
        ld l,(ix+BVY)
        ld h,(ix+BVY+1)
2:      sra h
        rr l
        djnz 2B
        ld e,(ix+BY)
        ld d,(ix+BY+1)
        add hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        call pocket_check
        ret c
        jp walls

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
pocket_check:
        ld a,(ix+BX+1)
        ld c,60
        ld d,0
        cp 68
        jr c,.xok
        ld c,196
        ld d,1
        cp 189
        jr nc,.xok
        or a
        ret
.xok:   sub c
        ld (pk_dx),a
        ld a,(ix+BY+1)
        ld c,28
        cp 36
        jr c,.yok
        ld c,164
        set 1,d
        cp 157
        jr nc,.yok
        or a
        ret
.yok:   sub c
        ld (pk_dy),a
        ld a,d
        ld (pk_idx),a
        ld a,(pk_dx)
        or a
        jp p,1F
        neg
1:      ld b,a
        ld c,a
        call mul8u
        push hl
        ld a,(pk_dy)
        or a
        jp p,2F
        neg
2:      ld b,a
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
        jr nc,3F
        ld e,a
        ld d,0
        ld hl,pk_ids
        add hl,de
        ld a,(ix+BID)
        ld (hl),a
        ld hl,pk_count
        inc (hl)
3:      call snd_pocket
        scf
        ret

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
        jr c,.x2
        jr z,.x2
        add hl,hl             ; 2*lim - x
        or a
        sbc hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        bit 7,(ix+BVX+1)
        call nz,bounce_vx
.x2:    ld a,200
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
        jr c,.y1
        jr z,.y1
        ex de,hl              ; hl = lim, de = over
        or a
        sbc hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        bit 7,(ix+BVX+1)
        call z,bounce_vx
.y1:    ld a,24
        add a,(ix+BR)
        ld h,a
        ld l,0
        ld e,(ix+BY)
        ld d,(ix+BY+1)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.y2
        jr z,.y2
        add hl,hl
        or a
        sbc hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        bit 7,(ix+BVY+1)
        call nz,bounce_vy
.y2:    ld a,168
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
        jr c,.done
        jr z,.done
        ex de,hl
        or a
        sbc hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        bit 7,(ix+BVY+1)
        call z,bounce_vy
.done:  ld a,(w_evt)
        or a
        ret z
        call snd_thud
        jp recompute

bounce_vx:
        ld l,(ix+BVX)
        ld h,(ix+BVX+1)
        call damp_neg
        ld (ix+BVX),l
        ld (ix+BVX+1),h
        ld a,1
        ld (w_evt),a
        ret
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
clamp_body:
        ld a,56
        add a,(ix+BR)
        cp (ix+BX+1)
        jr c,1F
        jr z,1F
        ld (ix+BX+1),a
        ld (ix+BX),0
1:      ld a,199
        sub (ix+BR)
        cp (ix+BX+1)
        jr nc,2F
        ld (ix+BX+1),a
        ld (ix+BX),255
2:      ld a,24
        add a,(ix+BR)
        cp (ix+BY+1)
        jr c,3F
        jr z,3F
        ld (ix+BY+1),a
        ld (ix+BY),0
3:      ld a,167
        sub (ix+BR)
        cp (ix+BY+1)
        ret nc
        ld (ix+BY+1),a
        ld (ix+BY),255
        ret

; recompute |v| and the per-tick friction decrement after a velocity change.
; |v| ~ max(M, 7/8 M + 1/2 m) (within ~3%); the decrement keeps the exact direction.
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
        jr nc,1F
        ex de,hl
1:      ld b,h
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
        ld hl,(rc_ax)
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
        jr nc,2F
        ld h,b
        ld l,c
2:      ld de,ACC*2
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
fric_comp:
        ld bc,(rc_s)
        xor a
        sbc hl,bc
        jr nc,1F
        add hl,bc
        jr 2F
1:      inc a
2:      ld e,7
3:      add hl,hl
        rla
        or a
        sbc hl,bc
        jr nc,4F
        add hl,bc
        jr 5F
4:      inc a
5:      dec e
        jr nz,3B
        ld b,a
        ld c,ACC
        call mul8u
        add hl,hl
        ld l,h
        ld h,0
        ret

; sweep and prune: on-board bodies kept sorted by x; only neighbours within 11 px are tested.
; ord_x / ord_y / ord_id are three consecutive 20-byte arrays.
collisions:
        ; gather all 20 bodies in last sub-step's order (a permutation in ord_id)
        ld hl,ord_id
        ld de,ord_x
        ld b,NB
.g:     push bc
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
        djnz .g
        ld a,NB
        ld (ord_n),a
        ; insertion sort by x (nearly sorted from the last sub-step)
        ld b,1
.is:    ld a,(ord_n)
        cp b
        jr z,.sorted
        ld a,b
        ld (sw_k),a
        ld e,b
        ld d,0
        ld hl,ord_x
        add hl,de
.isl:   ld a,(hl)
        dec hl
        cp (hl)
        jr nc,.isn
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
        jr nz,.isl
.isn:   inc b
        jr .is
.sorted:
        ld hl,ord_x
        ld a,(ord_n)
        ld (sw_left),a
.sa:    ld a,(sw_left)
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
.sb:    inc hl
        ld a,(hl)
        sub c
        cp 12
        jr nc,.sdone            ; everything further right is out of reach
        push hl
        ld de,60
        add hl,de
        ld a,(sw_fi)
        or (hl)
        and F_MOV               ; one of the pair must be moving
        jr z,.sbn
        ld de,-40
        add hl,de
        ld a,(sw_yi)
        ld b,a
        ld a,(hl)
        sub b
        add a,11
        cp 23
        jr nc,.sbn
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
        jr z,1F
        ld a,(ix+BF)
        and (iy+BF)
        and F_ON
        call nz,pair_test
1:      pop bc
.sbn:   pop hl
        ld a,(sw_cnt)
        dec a
        ld (sw_cnt),a
        jr nz,.sb
.sdone: pop hl
        inc hl
        jr .sa

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
        jr nz,1F
        inc a
        ld hl,16
        ld (pt_dx),hl
        ld hl,0
        ld (pt_dy),hl
1:      ld (pt_dist),a
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
        jp nz,.corr
        ld a,h
        or l
        jp z,.corr
        ld (pt_vrel),hl
        ; impulse factors (1+e)*m_other/(m_i+m_j) in 1/128, e = 0.95, mass ~ r^2
        ld bc,125*256+125
        ld a,(ix+BK)
        cp 3
        jr nz,2F
        ld bc,97*256+152
        jr 3F
2:      ld a,(iy+BK)
        cp 3
        jr nz,3F
        ld bc,152*256+97
3:      ld a,c
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
        jr z,4F
        ld a,(iy+BK)
        cp 3
        jr nz,5F
4:      ld a,1
        ld (touched),a
5:      call snd_click
.corr:  ; push the pair apart along the normal
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
sdiv64:
        ld a,h
        ld (sd_sign),a
        call abshl
        ld a,(pt_dist)
        ld c,a
        ld b,0
        xor a
        sbc hl,bc
        jr nc,1F
        add hl,bc
        jr 2F
1:      inc a
2:      ld e,6
3:      add hl,hl
        rla
        or a
        sbc hl,bc
        jr nc,4F
        add hl,bc
        jr 5F
4:      inc a
5:      dec e
        jr nz,3B
        ld l,a
        ld a,(sd_sign)
        bit 7,a
        ld a,l
        ret z
        neg
        ret
