; Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
; Licensed under the SANYALnet Labs Non-Commercial License.

; Carrom Arena ZX - ZX Spectrum 48K doubles Carrom with four autonomous robots.
;
; Keys: SPACE pause/resume   F fast/normal   M sound (all/effects/off)   R new match
;       Q quit to BASIC
;
; Audio: nanobeep-derived 2-channel beeper music plus an interrupt-safe long
; Bollywood-EDM-inspired in-game loop; both are based on techniques from
; tuklusan/ZX-Spectrum-1-Bit-Routines.  Text: 64-column font (font64.py).
; =============================================================================

        DEVICE ZXSPECTRUM48

; memory map (one CODE block at 32768; BASIC does CLEAR 32767)
;   $8000-       program, tables, font, music, RLE-packed board screen, variables
;   $E100-$F8FF  the board pixels, unpacked at start (display source and erase buffer)
;   $F900-$FBFF  the board attributes
;   $FDFD/$FE00  IM2 jump and vector table; stack below $FDF0
BGBUF   EQU 0xE100              ; clean copy of the board pixels
BGOFF   EQU BGBUF-0x4000
IM2TAB  EQU 0xFE00
IM2JP   EQU 0xFDFD
STACKTOP EQU 0xFDF0

        ORG 0x8000

NB      EQU 20                  ; 9 white, 9 black, queen, striker
QUEEN   EQU 18
STRIKER EQU 19
ACC     EQU 74                  ; board friction, 1/2048 px per tick^2
VMAX    EQU 12288               ; full-power striker, 6 px per tick

; body record
BX      EQU 0
BY      EQU 2
BVX     EQU 4
BVY     EQU 6
BS      EQU 8
BDX     EQU 10
BDY     EQU 12
BF      EQU 14
BK      EQU 15
BTX     EQU 16
BTY     EQU 17
BDRAWN  EQU 18
BPK     EQU 19
BR      EQU 20
BID     EQU 21
BSZ     EQU 24
F_ON    EQU 1
F_MOV   EQU 2

; 280 bytes — Boots the machine, starts the loop, and tries not to spill the tea.
start:
        di
        ld hl,vars_start
        ld (hl),0
        ld de,vars_start+1
        ld bc,vars_end-vars_start-1
        ldir
        ld (saved_sp),sp
        ld sp,STACKTOP
        ld hl,IM2TAB
        ld (hl),IM2JP&255
        ld de,IM2TAB+1
        ld bc,256
        ldir
        ld a,0xC3
        ld (IM2JP),a
        ld hl,isr
        ld (IM2JP+1),hl
        ld a,IM2TAB>>8
        ld i,a
        im 2
        xor a
        out (0xFE),a
        ld (fast),a
        ld (mute),a
        ld (paused),a
        ld (keys_last),a
        ; seed from the BASIC frame counter and R
        ld hl,(23672)
        ld a,r
        xor l
        ld l,a
        ld a,h
        or l
        jr nz,1F
        inc l
1:      ld (seed),hl
        ei
        ld hl,ord_id
        xor a
2:      ld (hl),a
        inc hl
        inc a
        cp NB
        jr c,2B
        ld hl,BOARD_RLE
        ld de,BGBUF
        call unrle
        call star_prepare
        ; keep the loaded picture up; replace its load notice with the small prompt
        ld hl,S_LOADBLANK
        ld b,17
        ld c,24
        call print64
        ld hl,S_PRESS
        ld b,17
        ld c,25
        call print64
        ld hl,0x5800+17*32+12
        ld b,7
4:      ld (hl),0xC6            ; flashing bright yellow
        inc hl
        djnz 4B
        ld hl,SONG_TITLE
        ld a,1
        call music_play
3:      xor a
        in a,(0xFE)
        cpl
        and 0x1F
        jr z,3B                 ; (if the theme ended first, still wait)
        call wait_release
        xor a
        ld (keys_last),a
        call draw_board
        call star_reset
        call gm_reset
        ld a,1
        ld (gm_run),a
        ld a,64
        ld (robot_pos),a
        ld (robot_pos+1),a
        ld (robot_pos+2),a
        ld (robot_pos+3),a
        ld a,0xFF
        ld (robot_drawn),a
        ld (robot_drawn+1),a
        ld (robot_drawn+2),a
        ld (robot_drawn+3),a
        ld a,128
        ld (robot_pos),a
        ld (robot_pos+2),a
        ld a,96
        ld (robot_pos+1),a
        ld (robot_pos+3),a
        call new_match
main_loop:
        ; frame sync: wait for the next frame only if this one has not already gone by
        ld a,(fast)
        or a
        jr nz,1F
        ld hl,(frames)
        ld de,(last_frame)
        or a
        sbc hl,de
        jr nz,1F
        halt
1:      ld hl,(frames)
        ld (last_frame),hl
        call read_keys
        ld a,(paused)
        or a
        jr nz,main_loop
        call star_step
        ld a,(note_t)           ; a sound-mode notice gives the status line back
        or a
        jr z,2F
        dec a
        ld (note_t),a
        call z,msg_show
2:      call run_phase
        call render
        call draw_robots
        jr main_loop


; ---------------------------------------------------------------- keys
; 257 bytes — Reads the keys and turns finger trouble into orderly decisions.

read_keys:
        ld c,0
        ld a,0x7F
        in a,(0xFE)
        bit 0,a
        jr nz,1F
        set 0,c                 ; SPACE
1:      bit 2,a
        jr nz,2F
        set 2,c                 ; M
2:      ld a,0xFD
        in a,(0xFE)
        bit 3,a
        jr nz,3F
        set 1,c                 ; F
3:      ld a,0xFB
        in a,(0xFE)
        bit 3,a
        jr nz,4F
        set 3,c                 ; R
4:      bit 0,a
        jr nz,5F
        set 4,c                 ; Q
5:      ld a,(keys_last)
        cpl
        and c
        ld b,a                  ; newly pressed
        ld a,c
        ld (keys_last),a
        bit 0,b
        call nz,k_pause
        bit 1,b
        call nz,k_fast
        bit 2,b
        call nz,k_mute
        bit 3,b
        call nz,k_restart
        bit 4,b
        jp nz,k_quit
        ret

k_pause:
        push bc
        ld a,(paused)
        xor 1
        ld (paused),a
        jr z,1F
        ld hl,S_PAUSED
        ld b,23
        call center64
        pop bc
        ret
1:      call msg_show
        pop bc
        ret
k_fast:
        ld a,(fast)
        xor 1
        ld (fast),a
        ret
; M cycles: music + effects -> effects only -> silence
k_mute:
        push bc
        ld a,(snd_mode)
        inc a
        cp 3
        jr c,1F
        xor a
1:      ld (snd_mode),a
        ld hl,S_SND0
        ld c,0
        or a
        jr z,2F
        ld hl,S_SND1
        inc c
        dec a
        jr z,2F
        ld hl,S_SND2
2:      ld a,c
        ld (music_off),a
        ld a,(snd_mode)
        cp 2
        ld a,0
        jr nz,3F
        inc a
3:      ld (mute),a
        ld b,23
        call center64
        ld a,100
        ld (note_t),a
        xor a
        out (0xFE),a
        pop bc
        ret
k_restart:
        push bc
        ; a stroke in progress leaves XOR marks on the screen; the new board redraws it all
        ld a,(phase)
        cp PH_HOLD
        jr nz,1F
        ld a,(timer)
        and 8
        call nz,halo_xor        ; halo currently shown: take it off
1:      call draw_board
        call star_redraw
        ld a,0xFF
        ld (robot_drawn),a
        ld (robot_drawn+1),a
        ld (robot_drawn+2),a
        ld (robot_drawn+3),a
        xor a
        ld (paused),a
        call stats_clear
        call new_match
        pop bc
        ret
k_quit:
        di
        xor a
        ld (gm_run),a
        out (0xFE),a
        exx
        ld hl,0x2758            ; BASIC needs H'L' restored before return
        exx
        ld a,0x3F
        ld i,a
        im 1
        ld iy,0x5C3A
        ld sp,(saved_sp)
        ei
        call 0x0D6B             ; CLS
        ret

        INCLUDE "core.asm"
        INCLUDE "game.asm"
        INCLUDE "groove.asm"
        INCLUDE "nanobeep.asm"

; HL = song, A = 1 to stop on a key.  nanobeep-derived player is blocking.
; 63 bytes — Plays blocking jingles, unpacks bytes, and waits for fingers to leave.
music_play:
        ld (nb_keyexit),a
        ld a,(music_off)
        or a
        ret nz
        ld a,(fast)
        or a
        ret nz
        push ix
        push iy
        call nb_play
        pop iy
        pop ix
        xor a
        out (0xFE),a
        ei
        ret

; wait until no key is held
; unpack RLE data HL to DE (n<128: n literals; n>=128: next byte n-126 times; 0 ends)
unrle:
        ld a,(hl)
        inc hl
        or a
        ret z
        jp m,1F
        ld c,a
        ld b,0
        ldir
        jr unrle
1:      sub 126
        ld b,a
        ld a,(hl)
        inc hl
2:      ld (de),a
        inc de
        djnz 2B
        jr unrle

wait_release:
        xor a
        in a,(0xFE)
        cpl
        and 0x1F
        jr nz,wait_release
        ret

; ---------------------------------------------------------------- text

S_RED:      db "RED",0
S_BLU:      db "BLU",0
S_BOARD:    db "BOARD ",0
S_GAME:     db " GAME ",0
S_DASH:     db " - ",0
S_BREAKS:   db " BREAKS",0
S_THINK:    db " THINKING",0
S_PLACED:   db " AT ",0
S_STRIKE:   db " STRIKING",0
S_BRKFOUL:  db "BREAK FOUL - TURN PASSES",0
S_BRKLOST:  db "3 MISSED BREAKS - TURN PASSES",0
S_BRKAGAIN: db "BREAK MISSED - TRY AGAIN",0
S_FOUL:     db "FOUL! STRIKER POCKETED",0
S_QCOVER:   db "QUEEN COVERED BY ",0
S_QPEND:    db "QUEEN IN - COVER HER!",0
S_QRET:     db "QUEEN BACK TO CENTRE",0
S_POCKETED: db "POCKETED ",0
S_OPPCOIN:  db "OPPONENT'S COIN IN",0
S_NOPOCKET: db "NOTHING POCKETED",0
S_CONT:     db " - AGAIN",0
S_PASS:     db " - NEXT",0
S_COLON:    db ": ",0
S_WINS:     db " WINS ",0
S_PTS:      db " PTS",0
S_GAMEOVER: db "GAME ",0
S_TO:       db " TO ",0
S_MATCH:    db "MATCH TO ",0
S_STARS:    db " - NEW MATCH",0
S_PAUSED:   db "** PAUSED - PRESS SPACE **",0
S_PRESS:    db "PRESS ANY KEY",0
S_LOADBLANK: db "                ",0
S_TITLE:    db "SANYALnet Labs  Carrom Arena",0
S_SND0:     db "SOUND: MUSIC AND EFFECTS",0
S_SND1:     db "SOUND: EFFECTS ONLY",0
S_SND2:     db "SOUND OFF",0
S_DUE:      db " DUE",0
S_NODUE:    db "    ",0
S_HPTS:     db "PTS ",0
S_HGAMES:   db "GAMES  ",0
S_HBOARDS:  db "BOARDS ",0
S_AGG:      db "AGGRESSIVE",0
S_BAL:      db "BALANCED",0
S_DEF:      db "DEFENSIVE",0
S_TRK:      db "TRICKSTER",0
PROFNAMES:  dw S_AGG,S_BAL,S_DEF,S_TRK

        INCLUDE "tables.asm"
        INCLUDE "font64.asm"
        INCLUDE "music.asm"

code_end:

; ---------------------------------------------------------------- variables (not saved)

        ORG code_end
vars_start:
saved_sp:       dw 0
frames:         dw 0
last_frame:     dw 0
seed:           dw 1
fast:           db 0
mute:           db 0
paused:         db 0
keys_last:      db 0
phase:          db 0
next_phase:     db 0
timer:          db 0
ticks:          dw 0
any_moving:     db 0
sub_shift:      db 3
w_evt:          db 0
touched:        db 0
pk_count:       db 0
pk_ids:         ds 20
pk_dx:          db 0
pk_dy:          db 0
pk_idx:         db 0
m8_sign:        db 0
m16_sign:       db 0
sd_sign:        db 0
sq_n:           ds 4
sq_root:        dw 0
sq_rem:         ds 3
er_col:         db 0
er_w:           db 0
ds_ptr:         dw 0
ds_w:           db 0
ds_h:           db 0
ds_col:         db 0
r_any:          db 0
rb_x:           db 0
rb_y:           db 0
rb_spr:         dw 0
robot_pos:      ds 4
robot_drawn:    ds 4
msg_buf:        ds 65
msg_pos:        db 0
rc_ax:          dw 0
rc_ay:          dw 0
rc_t:           ds 4
rc_s:           dw 0
ci:             db 0
cj:             db 0
pt_r16:         db 0
pt_r2:          dw 0
pt_dx:          dw 0
pt_dy:          dw 0
pt_d2:          dw 0
pt_dist:        db 0
pt_nx:          db 0
pt_ny:          db 0
pt_t:           ds 3
pt_vrel:        dw 0
pt_fj:          db 0
pt_ji:          dw 0
pt_jj:          dw 0
pt_push:        db 0
; match state
seat:           db 0            ; physical N/E/S/W turn position
player_at_seat: ds 4            ; logical player occupying each physical seat
pass_streak:    db 0            ; consecutive turn passes on this board
white_pair:     db 0            ; logical pair (players 0/2 or 1/3) playing white
break_off:      db 0
extra_board:    db 0            ; tied eighth-board replay uses a fresh breaker toss
extra_breaker:  db 0            ; logical player selected for that extra board
games_played:   db 0
boards_in_game: db 0
score:          ds 4            ; session PTS: low 0-99 for both pairs, then hundreds
boards_won:     ds 2            ; session board wins
games_won:      ds 2            ; session game wins
game_score:     ds 2            ; ICF score for the current game
left:           ds 2
dues:           ds 2
had:            ds 2
qstate:         db 0
qcover:         db 0
qpend:          db 0
break_made:     db 0
attempts:       db 0
gw:             db 0
; rules scratch
rA:             db 0
rcA:            db 0
rn:             db 0
rm:             db 0
rQ:             db 0
rS:             db 0
rbefore:        db 0
rright:         db 0
rdueout:        db 0
rqp:            db 0
rqc:            db 0
qa:             db 0
rcont:          db 0
rnewdue:        db 0
rowe:           db 0
rforced:        db 0
rgive:          db 0
rgiven:         db 0
rid:            db 0
rW:             db 0
rP:             db 0
rret            EQU rW          ; normal-stroke returned counts by coin colour
r_ownl:         db 0
r_oppl:         db 0
r_a:            db 0
r_b:            db 0
r_qcA:          db 0
r_qcB:          db 0
r_qon:          db 0
r_pa:           db 0
r_pb:           db 0
; hud
hp_p:           db 0
hp_col:         db 0
hp_c:           db 0
; thinking / plan
osc_u:          db 0
osc_d:          db 0
plan_u:         db 0
plan_vx:        dw 0
plan_vy:        dw 0
plan_speed:     dw 0
aim_n:          db 0
aim_t:          db 0
aim_len:        db 0
aim_x:          dw 0
aim_y:          dw 0
aim_sx:         dw 0
aim_sy:         dw 0
pf:             ds 8
ai_on:          ds 20
ai_u:           ds 20
ai_v:           ds 20
ai_t:           ds 10
ai_tn:          db 0
ai_k:           db 0
ai_mode:        db 0
ai_col:         db 0
ai_best:        dw 0
ai_bid:         db 0
ai_bp:          db 0
ai_bsu:         db 0
ai_bc64:        db 0
ev_id:          db 0
ev_p:           db 0
ev_pu:          db 0
ev_pv:          db 0
ev_cu:          db 0
ev_cv:          db 0
ev_dx:          db 0
ev_dy:          db 0
ev_lcp:         db 0
ev_nx:          db 0
ev_ny:          db 0
ev_gu:          db 0
ev_gv:          db 0
ev_s0:          db 0
ev_su:          db 0
ev_ux:          db 0
ev_uy:          db 0
ev_lsg:         db 0
ev_c64:         db 0
dv_len:         db 0
lg_su:          db 0
lg_dv:          db 0
sg_au:          db 0
sg_av:          db 0
sg_bu:          db 0
sg_bv:          db 0
sg_d:           db 0
sg_skip:        db 0
sg_ex:          db 0
sg_ey:          db 0
sg_l:           db 0
sg_l2:          dw 0
sg_dl:          dw 0
sg_dq:          dw 0
sg_umin:        dw 0
sg_vmin:        dw 0
sg_ou:          db 0
sg_ov:          db 0
sg_ox:          db 0
sg_oy:          db 0
fc_cx:          dw 0
fc_cy:          dw 0
fc_px:          dw 0
fc_py:          dw 0
fc_dx:          dw 0
fc_dy:          dw 0
fc_lcp:         dw 0
fc_gx:          dw 0
fc_gy:          dw 0
fc_sx:          dw 0
fc_sy:          dw 0
fc_ux:          dw 0
fc_uy:          dw 0
fc_lsg:         dw 0
fc_vc:          dw 0
fc_t:           ds 4
ln_t:           ds 4
fb_best:        dw 0
fb_id:          db 0
fb_su:          db 0
fb_pen:         db 0
fb_tier:        db 0
sg_noend:       db 0
ord_x:          ds 20
ord_y:          ds 20
ord_id:         ds 20
ord_f:          ds 20
ord_n:          db 0
sw_left:        db 0
sw_cnt:         db 0
sw_yi:          db 0
sw_idi:         db 0
sw_fi:          db 0
sw_k:           db 0
rb_old:         db 0
; moving space backdrop
star_far:       db 0
star_mid:       db 0
star_near:      db 0
star_frame:     db 0
star_tmp:       db 0
; sound
snd_mode:       db 0
music_off:      db 0
sfx_busy:       db 0
note_t:         db 0
nb_keyexit:     db 0
nb_speed:       dw 0
nb_loop:        dw 0
nb_seq:         dw 0
gm_run:         db 0
gm_f:           db 0
gm_left:        db 0
gm_songp:       dw 0
gm_patp:        dw 0
gm_note:        db 0
gm_nage:        db 0
gm_drum:        db 0
gm_dage:        db 0
gm_np:          dw 0
gm_hi:          db 0
gm_lo:          dw 0
; text
c64_pad:        db 0
title_x:        db 0
title_bits:     db 0
nd_d:           ds 3
BODIES:         ds NB*BSZ
vars_end:

        ASSERT vars_end < BGBUF
        SAVEBIN "carrom.bin",start,code_end-start
        DISPLAY "code ",/D,code_end-start," bytes (",start,"-",code_end,"), vars end ",vars_end
