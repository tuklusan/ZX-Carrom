; Copyright (c) 2026 Supratim Sanyal of SANYALnet Labs.
; Licensed under the SANYALnet Labs Non-Commercial License.

; Carrom Arena ZX - game: match flow, ICF rules, the Carrom Engine, HUD.

PH_NEWBOARD     EQU 0
PH_THINK0       EQU 1
PH_THINK        EQU 2
PH_PLACE        EQU 3
PH_HOLD         EQU 4
PH_AIM          EQU 5
PH_MOVE         EQU 6
PH_RESOLVE      EQU 7
PH_WAIT         EQU 8
PH_AFTERBOARD   EQU 9
PH_AFTERGAME    EQU 10
PH_NEWMATCH     EQU 11
PASS_REPLAY_LIMIT EQU 12       ; ICF 137: four doubles players passing three times each

QA_NONE EQU 0
QA_PEND EQU 1
QA_COVER EQU 2
QA_RET  EQU 3

AIM_K0  EQU 7
VB_HALF EQU -33         ; baseline in seat frame, half pixels

; 40 bytes — Dispatches each frame to the right phase with minimal ceremony.
run_phase:
        ld a,(phase)
        add a,a
        ld l,a
        ld h,0
        ld de,PHTAB
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)
PHTAB:  dw ph_newboard,ph_think0,ph_think,ph_place,ph_hold,ph_aim,ph_move
        dw ph_resolve,ph_wait,ph_afterboard,ph_aftergame,ph_newmatch

; ---------------------------------------------------------------- match / game / board
; 351 bytes — Starts matches, boards, and turns without asking for a committee.

new_match:
        call reset_player_map
        call record_progress
        xor a
        ld (games_played),a
        ld (gw),a
        ld c,4
        call rand_n
        ld (break_off),a        ; the toss: which seat breaks the first board
new_game:
        xor a
        ld (game_score),a
        ld (game_score+1),a
        ld (boards_in_game),a
        ld (extra_board),a
        ld (extra_breaker),a
        ld a,PH_NEWBOARD
        ld (phase),a
        ret

ph_newmatch:
        jr new_match

ph_wait:
        ld hl,timer
        ld a,(hl)
        or a
        jr z,1F
        dec (hl)
        ret
1:      ld a,(next_phase)
        ld (phase),a
        ret

wait_then:      ; A = frames, C = next phase
        ld (timer),a
        ld a,c
        ld (next_phase),a
        ld a,PH_WAIT
        ld (phase),a
        ret

ph_newboard:
        call setup_board
        call render
        call hud
        call msg_clear
        ld hl,S_BOARD
        call msg_s
        ld a,(boards_in_game)
        inc a
        call msg_n
        ld hl,S_GAME
        call msg_s
        ld a,(games_played)
        inc a
        call msg_n
        ld hl,S_DASH
        call msg_s
        call msg_mover
        ld hl,S_BREAKS
        call msg_s
        call msg_show
        ld a,90
        ld c,PH_THINK0
        jp wait_then

setup_board:
        call reset_board_pixels
        ; ICF extra board: a tied eighth board gets a fresh logical breaker toss.
        ; Normal boards keep the ordinary ICF 49 rotation and ignore stale toss data.
        ld a,(extra_board)
        or a
        jr z,.normal_breaker
        xor a
        ld (extra_board),a      ; consume the one-shot extra-board selection
        ld a,(extra_breaker)
        and 3
        jr .breaker_ready
.normal_breaker:
        ld a,(boards_in_game)
        ld hl,games_played
        add a,(hl)
        ld hl,break_off
        add a,(hl)
        and 3
.breaker_ready:
        ld c,a
        and 1
        ld (white_pair),a       ; the breaker's logical pair plays white (ICF 43)
        ld a,c
        call seat_for_player
        jr nc,.seat_ok
        ; A corrupt map is not allowed to leak an out-of-range physical seat.
        ; Recover to the fresh-match identity map; direct callers can detect carry.
        call reset_player_map
        ld a,c
.seat_ok:
        ld (seat),a
        ld ix,BODIES
        ld b,0
.lp:    ld (ix+BID),b
        ld a,b
        ld c,0
        cp 9
        jr c,1F
        ld c,1
        cp 18
        jr c,1F
        ld c,2
        jr z,1F
        ld c,3
1:      ld (ix+BK),c
        ld (ix+BR),4
        ld a,c
        cp 3
        jr nz,2F
        ld (ix+BR),5
2:      call body_stop
        ld (ix+BF),F_ON
        ld (ix+BDRAWN),0
        ld (ix+BX),0
        ld (ix+BX+1),128
        ld (ix+BY),0
        ld (ix+BY+1),96
        ld de,BSZ
        add ix,de
        inc b
        ld a,b
        cp NB
        jr c,.lp
        xor a
        ld (BODIES+STRIKER*BSZ+BF),a
        ; ICF 41: the formation, turned by a random angle
        ld c,24
        call rand_n
        ld b,a
        ld c,72
        call mul8u
        ld de,FORMATION
        add hl,de
        ld ix,BODIES
        ld b,18
.f:     ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,0x8000
        add hl,de
        ld (ix+BX),l
        ld (ix+BX+1),h
        pop hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,0x6000
        add hl,de
        ld (ix+BY),l
        ld (ix+BY+1),h
        pop hl
        ld de,BSZ
        add ix,de
        djnz .f
        ld a,9
        ld (left),a
        ld (left+1),a
        xor a
        ld (dues),a
        ld (dues+1),a
        ld (had),a
        ld (had+1),a
        ld (qstate),a
        ld (qcover),a
        ld (qpend),a
        ld (break_made),a
        ld (attempts),a
        ld (pass_streak),a
        ret

; logical-player mapping.  seat remains the physical N/E/S/W turn position.
reset_player_map:
        ld hl,player_at_seat
        xor a
        ld (hl),a
        inc hl
        inc a
        ld (hl),a
        inc hl
        inc a
        ld (hl),a
        inc hl
        inc a
        ld (hl),a
        ret

; A = physical seat -> A = logical player.  Physical callers keep seat geometry separate.
logical_for_seat:
        and 3
        ld e,a
        ld d,0
        ld hl,player_at_seat
        add hl,de
        ld a,(hl)
        ret

; current mover's logical player
logical_player:
        ld a,(seat)
        jp logical_for_seat

; current mover's logical pair (0 = players 0/2, 1 = players 1/3)
mover_pair:
        call logical_player
        and 1
        ret

; A = logical player -> A = physical seat, carry set and A=$FF if absent.
; Exactly four entries are examined so a damaged map cannot spin forever.
seat_for_player:
        ld c,a
        ld hl,player_at_seat
        ld b,4
        xor a
1:      ld e,(hl)
        ld d,a
        ld a,e
        cp c
        ld a,d
        jr z,2F
        inc hl
        inc a
        djnz 1B
        ld a,0xFF
        scf
        ret
2:      or a                    ; clear carry on success
        ret

; Carry clear only when all four logical players occur exactly once.
; With four slots, finding 0,1,2,3 proves there can be no duplicate or stray value.
validate_player_map:
        xor a
1:      ld b,a
        push bc
        call seat_for_player
        pop bc
        ret c
        ld a,b
        inc a
        cp 4
        jr c,1B
        ret

; Every logical player moves one physical seat clockwise between games.
; Corrupt input is rejected with carry set, recovered to identity, then rotated.
rotate_players_right:
        call validate_player_map
        ld c,0
        jr nc,.rotate
        call reset_player_map
        ld c,1
.rotate:
        ld a,(player_at_seat+3)
        ld b,a
        ld a,(player_at_seat+2)
        ld (player_at_seat+3),a
        ld a,(player_at_seat+1)
        ld (player_at_seat+2),a
        ld a,(player_at_seat)
        ld (player_at_seat+1),a
        ld a,b
        ld (player_at_seat),a
        ld a,c
        or a
        ret z
        scf
        ret

; colour (0 white, 1 black) of the side to move
mover_colour:
        call mover_pair
pair_colour:            ; A = logical pair -> A = colour
        ld b,a
        ld a,(white_pair)
        cp b
        ld a,0
        ret z
        inc a
        ret

; ---------------------------------------------------------------- thinking
; 622 bytes — Places, aims, and animates a shot while the robots look thoughtful.

ph_think0:
        ld ix,BODIES+STRIKER*BSZ
        call body_stop
        ld (ix+BF),F_ON
        xor a
        ld (osc_u),a
        ld a,2
        ld (osc_d),a
        xor a
        call set_striker_u
        call msg_clear
        call msg_mover
        ld a,' '
        call msg_c
        call msg_profile
        ld hl,S_THINK
        call msg_s
        call msg_show
        call ai_begin
        ld a,70
        ld (timer),a
        ld a,PH_THINK
        ld (phase),a
        ret

ph_think:
        ; the striker sweeps the full baseline while the robot thinks (locked invariant 5)
        ld a,(osc_d)
        ld b,a
        ld a,(osc_u)
        add a,b
        ld (osc_u),a
        cp 56
        jr z,1F
        cp -56&255
        jr nz,2F
1:      ld a,(osc_d)
        neg
        ld (osc_d),a
2:      ld a,(osc_u)
        call set_striker_u
        ld hl,timer
        ld a,(hl)
        or a
        jr z,3F
        dec (hl)
3:      call ai_step
        ret nc
        ld a,(timer)
        or a
        ret nz
        call ai_finish
        ret c                    ; no legal striker placement: pass path already scheduled
        ld a,PH_PLACE
        ld (phase),a
        ret

; A = u (signed pixels along the baseline) -> striker position
set_striker_u:
        ld l,a
        rla
        sbc a,a
        ld h,a
        ld de,-66
        call from_seat16
        ld a,l
        add a,128
        ld (BODIES+STRIKER*BSZ+BX+1),a
        ld a,e
        add a,96
        ld (BODIES+STRIKER*BSZ+BY+1),a
        xor a
        ld (BODIES+STRIKER*BSZ+BX),a
        ld (BODIES+STRIKER*BSZ+BY),a
        ret

; seat frame: u along the baseline, v forward (toward the far side)
; HL=bx DE=by -> HL=u DE=v
to_seat16:
        ld a,(seat)
        or a
        jr z,.n
        dec a
        jr z,.e
        dec a
        jr z,.s
        ex de,hl            ; W: u=-by v=bx
        jp neghl
.n:     jp neghl            ; N: u=-bx v=by
.e:     call neghl          ; E: u=by v=-bx
        ex de,hl
        ret
.s:     ex de,hl            ; S: u=bx v=-by
        call neghl
        ex de,hl
        ret
; HL=u DE=v -> HL=bx DE=by
from_seat16:
        ld a,(seat)
        or a
        jr z,.n
        dec a
        jr z,.e
        dec a
        jr z,.s
        call neghl          ; W: bx=v by=-u
        ex de,hl
        ret
.n:     jp neghl            ; N: bx=-u by=v
.e:     ex de,hl            ; E: bx=-v by=u
        jp neghl
.s:     ex de,hl            ; S: bx=u by=-v
        call neghl
        ex de,hl
        ret

ph_place:
        ld a,(plan_u)
        ld b,a
        ld a,(osc_u)
        sub b
        jr z,.there
        jp p,.pos
        cp -2&255
        jr nc,.there
        ld a,(osc_u)
        add a,2
        jr .set
.pos:   cp 3
        jr c,.there
        ld a,(osc_u)
        sub 2
.set:   ld (osc_u),a
        jp set_striker_u
.there: ld a,(plan_u)
        ld (osc_u),a
        call set_striker_u
        call render
        ; "Striker placed at (x,y) - striking in 1s" (locked invariant 2)
        call msg_clear
        call msg_mover
        ld hl,S_PLACED
        call msg_s
        ld a,(BODIES+STRIKER*BSZ+BX+1)
        call msg_n
        ld a,','
        call msg_c
        ld a,(BODIES+STRIKER*BSZ+BY+1)
        call msg_n
        ld hl,S_STRIKE
        call msg_s
        call msg_show
        ld a,48
        ld (timer),a
        ld a,PH_HOLD
        ld (phase),a
        ret

ph_hold:
        ld a,(timer)
        or a
        jr z,.go
        and 7
        call z,halo_xor
        ld hl,timer
        dec (hl)
        ret
.go:    ; aim preview: the line grows from the striker to its strike-force length over 2 s
        xor a
        ld (aim_n),a
        ld (aim_t),a
        ld hl,(plan_speed)
        ld a,h
        add a,12
        ld (aim_len),a
        call aim_reset
        ld a,PH_AIM
        ld (phase),a
        ret

halo_xor:
        ld hl,HALO
.lp:    ld a,(hl)
        cp 128
        ret z
        ld b,a
        inc hl
        ld c,(hl)
        inc hl
        push hl
        ld a,(BODIES+STRIKER*BSZ+BX+1)
        add a,b
        ld b,a
        ld a,(BODIES+STRIKER*BSZ+BY+1)
        add a,c
        ld c,a
        call plot_xor
        pop hl
        jr .lp

aim_reset:
        ; accumulator = striker + K0*step
        ld a,(BODIES+STRIKER*BSZ+BX+1)
        ld h,a
        ld l,128
        ld (aim_x),hl
        ld a,(BODIES+STRIKER*BSZ+BY+1)
        ld h,a
        ld (aim_y),hl
        ld b,AIM_K0
1:      push bc
        call aim_adv
        pop bc
        djnz 1B
        ret
aim_adv:
        ld hl,(aim_x)
        ld de,(aim_sx)
        add hl,de
        ld (aim_x),hl
        ld hl,(aim_y)
        ld de,(aim_sy)
        add hl,de
        ld (aim_y),hl
        ret
; plot the next point of the line; carry set when it would leave the play area
aim_plot:
        ld a,(aim_x+1)
        cp 57
        jr c,.out
        cp 199
        jr nc,.out
        ld b,a
        ld a,(aim_y+1)
        cp 25
        jr c,.out
        cp 167
        jr nc,.out
        ld c,a
        call plot_xor
        call aim_adv
        or a
        ret
.out:   scf
        ret

ph_aim:
        ld hl,aim_t
        inc (hl)
        ld a,(hl)
        cp 100
        jr nc,.full
        ; target points = len * t / 100
        ld b,a
        ld a,(aim_len)
        ld c,a
        call mul8u
        ld c,100
        call div16_8
        ld b,l
.grow:  ld a,(aim_n)
        cp b
        ret nc
        push bc
        call aim_plot
        pop bc
        jr c,.clip
        ld hl,aim_n
        inc (hl)
        jr .grow
.clip:  ld a,(aim_n)
        ld (aim_len),a
        ret
.full:  cp 112
        ret c
        ; erase the line and strike
        call aim_reset
        ld a,(aim_n)
        or a
        jr z,.go
        ld b,a
1:      push bc
        call aim_plot
        pop bc
        djnz 1B
.go:    ld ix,BODIES+STRIKER*BSZ
        ld hl,(plan_vx)
        ld (ix+BVX),l
        ld (ix+BVX+1),h
        ld hl,(plan_vy)
        ld (ix+BVY),l
        ld (ix+BVY+1),h
        call recompute
        xor a
        ld (pk_count),a
        ld (touched),a
        ld hl,0
        ld (ticks),hl
        call snd_flick
        ld a,PH_MOVE
        ld (phase),a
        ret

ph_move:
        call phys_tick
        ld hl,(ticks)
        inc hl
        ld (ticks),hl
        ld a,(any_moving)
        or a
        jr z,.done
        ld de,1500
        or a
        sbc hl,de
        ret c
        ld ix,BODIES
        ld b,NB
1:      call body_stop
        ld de,BSZ
        add ix,de
        djnz 1B
.done:  ld a,PH_RESOLVE
        ld (phase),a
        ret

; ---------------------------------------------------------------- the rules (ICF Laws, doubles)
; 2001 bytes — Applies the Carrom rules, including the queen's impressive paperwork.

; A = pocketed coin id 0..17.  Return C = coin colour and remember that this
; colour has reached a pocket during the current board.  HL/B are preserved.
record_coin_history:
        cp 9
        ccf
        ld a,0
        adc a,0
        ld c,a
        ld e,a
        ld d,0
        push hl
        ld hl,had
        add hl,de
        ld (hl),1
        pop hl
        ret

ph_resolve:
        call mover_pair
        ld (rA),a
        call mover_colour
        ld (rcA),a
        xor a
        ld (rn),a
        ld (rm),a
        ld (rQ),a
        ld (rS),a
        ld (qa),a
        ld (rcont),a
        ld (rnewdue),a
        ld (rgiven),a
        ld a,(pk_count)
        or a
        jr z,.counted
        ld b,a
        ld hl,pk_ids
.c:     ld a,(hl)
        inc hl
        cp STRIKER
        jr nz,1F
        ld a,1
        ld (rS),a
        jr .cn
1:      cp QUEEN
        jr nz,2F
        ld a,1
        ld (rQ),a
        jr .cn
2:      call record_coin_history
        ld a,(rcA)
        cp c
        jr nz,3F
        ld a,(rn)
        inc a
        ld (rn),a
        jr .cn
3:      ld a,(rm)
        inc a
        ld (rm),a
.cn:    djnz .c
.counted:
        ; ICF 44, 45: the break is made once the striker touches a coin
        ld a,(break_made)
        or a
        jr nz,.broken
        ld a,(touched)
        or a
        jr nz,.mkbreak
        ld a,(rS)
        or a
        jr z,.att
        xor a
        ld (attempts),a
        ld hl,S_BRKFOUL
        jp turn_pass
.att:   ld hl,attempts
        inc (hl)
        ld a,(hl)
        cp 3
        jr c,.again
        ld (hl),0
        ld hl,S_BRKLOST
        jp turn_pass
.again: ld hl,S_BRKAGAIN
        jp turn_stay
.mkbreak:
        ld a,1
        ld (break_made),a
        xor a
        ld (attempts),a
.broken:
        ; coins left on the board
        ld a,(rcA)
        ld e,a
        ld d,0
        ld hl,left
        add hl,de
        ld a,(hl)
        ld (rbefore),a
        ld b,a
        ld a,(rn)
        ld c,a
        ld a,b
        sub c
        jr nc,4F
        xor a
4:      ld (hl),a
        ld a,e
        xor 1
        ld e,a
        ld hl,left
        add hl,de
        ld a,(rm)
        ld c,a
        ld a,(hl)
        sub c
        jr nc,5F
        xor a
5:      ld (hl),a
        ; facts
        ld a,(rcA)
        ld e,a
        ld hl,had
        add hl,de
        ld a,(hl)
        ld (rright),a
        ld hl,dues
        add hl,de
        ld a,(hl)
        ld (rdueout),a
        ld a,(qstate)
        cp 1
        ld a,0
        jr nz,6F
        inc a
6:      ld (rqp),a
        ld a,(qstate)
        cp 2
        ld a,0
        jr nz,7F
        ld a,(qcover)
7:      ld (rqc),a
        ; ---- the queen and the turn (ICF 48, 92-101)
        ld a,(rS)
        or a
        jr z,.nos
        ld a,1
        ld (rnewdue),a           ; 72a: a pocketed striker costs a coin
        ld a,(rqp)
        or a
        jr z,.s2
        ld a,(rn)
        or a
        jr z,.s1r
        ld a,(qpend)
        cp 2
        jr nc,.s1r
        ld a,2
        ld (qpend),a
        ld a,QA_PEND
        ld (qa),a
        ld a,1
        ld (rcont),a             ; 101a: one more stroke to cover
        jp .qdone
.s1r:   ld a,QA_RET
        ld (qa),a
        call n_cont
        jp .qdone
.s2:    ld a,(rQ)
        or a
        jr z,.s3
        ld a,QA_RET
        ld (qa),a
        ; Queen + own coin(s) + striker: all returns are due, and play continues.
        call n_cont             ; Z returns set only for the no-own-coin case
        jp nz,.qdone
.s2_no_own:
        ; Queen + striker with no own coin keeps the separate restricted case.
        ld a,(rbefore)
        cp 9
        jp z,.qdone
        ld a,(rdueout)
        or a
        jp nz,.qdone
        ld a,(rright)
        or a
        jp z,.qdone
        ld a,1
        ld (rcont),a
        jp .qdone
.s3:    call n_cont
        jp .qdone
.nos:   ld a,(rqp)
        or a
        jr z,.nq
        ld a,(rn)
        or a
        jr z,.nqr
        ld a,QA_COVER            ; 96: covered by a coin of his own
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr .qdone
.nqr:   ld a,QA_RET              ; 96: not covered, she goes back
        ld (qa),a
        jr .qdone
.nq:    ld a,(rQ)
        or a
        jr z,.nn
        ld a,(rdueout)
        or a
        jr nz,.nqr               ; 95b
        ld a,(rn)
        or a
        jr nz,.q3
        ld a,(rm)
        or a
        jr nz,.nqr               ; 125
        ld a,(rright)
        or a
        jr z,.nqr                ; 95a: no right to the queen yet
        ld a,QA_PEND             ; 92
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr .qdone
.q3:    ld a,(rbefore)
        cp 9
        jr nz,.q4
        ld a,(rn)
        cp 1
        jr nz,.q4
        ld a,QA_PEND             ; 97b: has to be covered
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr .qdone
.q4:    ld a,QA_COVER            ; 97a
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr .qdone
.nn:    call n_cont              ; 48
.qdone:
        ; Pocket-event colour history was recorded while pk_ids were counted.
        ; Returns later in this routine must not erase that board-long fact.
        ; ---- end of the board? (ICF 52, 53, 102-112)
        call board_result
        jp c,finish_board
        ; ---- the queen's fate
        ld a,(qa)
        cp QA_PEND
        jr nz,9F
        ld a,1
        ld (qstate),a
        ld a,(qpend)
        or a
        jr nz,9F
        inc a
        ld (qpend),a
9:      ld a,(qa)
        cp QA_COVER
        jr nz,10F
        ld a,2
        ld (qstate),a
        ld a,(rcA)
        inc a
        ld (qcover),a
        xor a
        ld (qpend),a
10:     ; ---- coins to put back: striker-forced own coins and Due for both colours
        ; Publish the mover's newly incurred Due before any placement can fail.
        ld a,(rcA)
        ld e,a
        ld d,0
        ld hl,dues
        add hl,de
        ld a,(rnewdue)
        add a,(hl)
        ld (hl),a
        ld a,(qa)
        cp QA_RET
        jr nz,.queen_done
        ld hl,FREESPOTS          ; ICF 93, 94: the queen goes back to the centre
        call find_spot
        jr nc,.queen_spot
        ; Impossible placement: keep a nonzero Queen state and replay cleanly.
        ld a,1
        ld (qstate),a
        xor a                    ; PH_NEWBOARD
        ld (phase),a
        ret
.queen_spot:
        ld ix,BODIES+QUEEN*BSZ
        call put_back
        xor a
        ld (qstate),a
        ld (qpend),a
.queen_done:
        ld a,(rcA)
        xor 1                    ; settle the other colour's old Due first
        ld c,0
due_other_call:
        call return_colour
        ld c,0
        ld a,(rS)
        or a
        jr z,11F
        ld a,(rn)
        ld c,a                   ; striker forces these mover-colour coins back
11:     ld a,(rcA)
        call return_colour       ; mover last leaves rgiven compatible with old accounting
        call stats_stroke
        call c,stats_clear
        ; ---- the message and the turn
        call msg_clear
        ld a,(rS)
        or a
        jr z,.m1
        ld hl,S_FOUL
        call msg_s
        jr .mturn
.m1:    ld a,(qa)
        cp QA_COVER
        jr nz,.m2
        ld hl,S_QCOVER
        call msg_s
        ld a,(rA)
        call msg_pair
        jr .mturn
.m2:    cp QA_PEND
        jr nz,.m3
        ld hl,S_QPEND
        call msg_s
        jr .mturn
.m3:    cp QA_RET
        jr nz,.m4
        ld hl,S_QRET
        call msg_s
        jr .mturn
.m4:    ld a,(rn)
        or a
        jr z,.m5
        ld hl,S_POCKETED
        call msg_s
        ld a,(rn)
        call msg_n
        jr .mturn
.m5:    ld a,(rm)
        or a
        jr z,.m6
        ld hl,S_OPPCOIN
        call msg_s
        jr .mturn
.m6:    ld hl,S_NOPOCKET
        call msg_s
.mturn: ld a,(rcont)
        or a
        jr z,.adv
        ld hl,S_CONT
        call msg_s
        call record_progress     ; a lawful continuation breaks the pass sequence
        jr .fin
.adv:   ld hl,S_PASS
        call msg_s
        call pass_turn
        ret c                    ; threshold schedules a clean replay of this board
.fin:   call msg_show
        call render
        call hud
        ld a,50
        ld c,PH_THINK0
        jp wait_then

n_cont: ld a,(rn)
        or a
        ret z
        ld a,1
        ld (rcont),a
        ret

; One actual turn pass. Carry means ICF 137 reached three passes by each of
; the four doubles players, so this same board is scheduled for a clean replay.
pass_turn:
        ld hl,pass_streak
        inc (hl)
        ld a,(hl)
        cp PASS_REPLAY_LIMIT
        jr c,.advance
        xor a
        ld (hl),a
        ld a,PH_NEWBOARD
        ld (phase),a
        scf
        ret
.advance:
        ld a,(seat)
        inc a
        and 3
        ld (seat),a
        or a                    ; clear carry
        ret

record_progress:
        xor a
        ld (pass_streak),a
        ret

turn_pass:      ; HL = message, the turn goes to the next seat
        push hl
        call msg_clear
        pop hl
        call msg_s
        call pass_turn
        ret c
        jr turn_end
turn_stay:
        push hl
        call msg_clear
        pop hl
        call msg_s
turn_end:
        call msg_show
        call render
        call hud
        ld a,50
        ld c,PH_THINK0
        jp wait_then


; A = coin colour, C = forced returns before Due. Returns that colour only.
; rret[colour] receives the physical return count for session accounting.
return_colour:
        push af                   ; colour rides the stack while the bodies misbehave
        xor a
        ld (rgiven),a
        pop af
        push af
        ld e,a
        ld d,0
        ld hl,dues
        add hl,de
        ld a,(hl)
        add a,c                  ; wanted = forced + Due
        ld (rgive),a
        ld a,e
        neg
        and 9                    ; colour 0 -> body 0, colour 1 -> body 9
        ld (rid),a
        ld b,9
.loop:  push bc
        ld a,(rgiven)
        ld hl,rgive
        cp (hl)
        jr nc,.next
        ld a,(rid)
        call body_ptr
        ld a,(ix+BF)
        and F_ON
        jr nz,.next
        ld hl,DUESPOTS
        call find_spot
        jr nc,2F
        ld hl,FREESPOTS
        call find_spot
        jr c,.next
2:      call put_back
        ld hl,rgiven
        inc (hl)
.next:  ld hl,rid
        inc (hl)
        pop bc
        djnz .loop
        pop af
        ld e,a
        ld d,0
        ld a,(rgiven)
        ld b,a
        ld hl,left
        add hl,de
        add a,(hl)
        ld (hl),a
        ld a,b
        sub c
        jr nc,3F
        xor a
3:      ld b,a                   ; B = returns that actually pay Due
        ld hl,dues
        add hl,de
        ld a,(hl)
        sub b                    ; B cannot exceed this Due: returns stop at wanted
        ld (hl),a
        ld hl,rret
        add hl,de
        ld a,(rgiven)
        ld (hl),a
        ret

; IX = body A
body_ptr:
        ld b,a
        ld c,BSZ
        call mul8u
        ld de,BODIES
        add hl,de
        push hl
        pop ix
        ret

put_back:       ; IX = body, B = x, C = y (pixels)
        call body_stop
        ld (ix+BX+1),b
        ld (ix+BX),0
        ld (ix+BY+1),c
        ld (ix+BY),0
        ld (ix+BF),F_ON
        ret

; first spot from table HL where a coin touches nothing: B=x C=y, carry if none
find_spot:
.lp:    ld a,(hl)
        cp 128
        jr z,.none
        add a,128
        ld b,a
        inc hl
        ld a,(hl)
        add a,96
        ld c,a
        inc hl
        push hl
        call spot_free
        pop hl
        jr c,.lp
        or a
        ret
.none:  scf
        ret

; carry if a coin at (B,C) would overlap a coin on the board. Preserves BC.
spot_free:
        push ix
        ld ix,BODIES
        ld e,19
.lp:    ld a,(ix+BF)
        and F_ON
        jr z,.nx
        ld a,(ix+BX+1)
        sub b
        jp p,1F
        neg
1:      cp 10
        jr nc,.nx
        ld h,a
        ld a,(ix+BY+1)
        sub c
        jp p,2F
        neg
2:      cp 10
        jr nc,.nx
        ld l,a
        push bc
        push de
        ld b,h
        ld c,h
        push hl
        call mul8u
        ex (sp),hl
        ld b,l
        ld c,l
        call mul8u
        pop de
        add hl,de
        pop de
        pop bc
        push de
        ld de,73
        or a
        sbc hl,de
        pop de
        jr nc,.nx
        pop ix
        scf
        ret
.nx:    push de
        ld de,BSZ
        add ix,de
        pop de
        dec e
        jr nz,.lp
        pop ix
        or a
        ret

; ---- ICF 52, 53, 102-112: does this stroke end the board?  carry -> rW, rP
board_result:
        ; own_last / opp_last
        xor a
        ld (r_ownl),a
        ld (r_oppl),a
        ld a,(rcA)
        ld e,a
        ld d,0
        ld hl,left
        add hl,de
        ld a,(hl)
        ld (r_a),a
        ld a,(rn)
        or a
        jr z,1F
        ld a,(r_a)
        or a
        jr nz,1F
        inc a
        ld (r_ownl),a
1:      ld a,e
        xor 1
        ld e,a
        ld hl,left
        add hl,de
        ld a,(hl)
        ld (r_b),a
        ld a,(rm)
        or a
        jr z,2F
        ld a,(r_b)
        or a
        jr nz,2F
        inc a
        ld (r_oppl),a
2:      ld a,(r_ownl)
        ld hl,r_oppl
        or (hl)
        ret z                    ; both colours still have coins (carry clear)
        ; queen facts
        ld a,(rcA)
        inc a
        ld b,a                   ; my colour code
        ld a,(rqc)
        cp b
        ld a,0
        jr nz,3F
        inc a
3:      ld c,a
        ld a,(qa)
        cp QA_COVER
        jr nz,4F
        ld c,1
4:      ld a,c
        ld (r_qcA),a
        ld a,(rqc)
        or a
        jr z,5F
        cp b
        ld a,1
        jr nz,6F
5:      xor a
6:      ld (r_qcB),a
        ld a,(rQ)
        ld hl,rqp
        or (hl)
        ld hl,rqc
        or (hl)
        ld a,0
        jr nz,7F
        inc a
7:      ld (r_qon),a
        ld a,(rA)
        ld (r_pa),a
        xor 1
        ld (r_pb),a
        ld a,(rS)
        or a
        jp z,.nostrk
        ; -- the striker went down with the last coin(s)
        ld a,(r_pb)
        ld (rW),a
        ld a,(r_ownl)
        ld hl,r_oppl
        and (hl)
        jr z,.s_one
        ld a,(rQ)
        or a
        jr nz,.s_a               ; 109a
        ld a,(r_qcA)
        or a
        jr z,.s_a
        ld a,2                   ; 110a
        jp .ret
.s_a:   call qv_b
        inc a
        jp .ret
.s_one: ld a,(r_ownl)
        or a
        jr z,.s_opp
        ld a,(r_qon)
        or a
        ret z                    ; the coin goes back instead (ICF 73/98/101)
        call qv_b                ; 108a
        inc a
        jp .ret
.s_opp: ld a,(r_qon)
        or a
        jr z,.s_o2
        call qc_b                ; 111a
        jr .s_o3
.s_o2:  ld a,(r_qcB)
        or a
        jr z,.s_o3
        call qc_b
.s_o3:  ld hl,r_a
        add a,(hl)
        inc a
        jp .ret
.nostrk:
        ld a,(r_ownl)
        ld hl,r_oppl
        and (hl)
        jr z,.n_one
        ; both colours finished by one stroke
        ld a,(rqp)
        ld hl,rQ
        or (hl)
        jr nz,.n_bA              ; 102a, 104a
        ld a,(r_qon)
        or a
        jr z,.n_b2
        ld a,(r_pb)              ; 105a
        ld (rW),a
        call qv_b
        jr .ret
.n_b2:  ld a,(r_qcA)
        or a
        jr nz,.n_bA
        ld a,(r_pa)
        ld (rW),a
        ld a,1
        jr .ret
.n_bA:  ld a,(r_pa)
        ld (rW),a
        call qv_a
        jr .ret
.n_one: ld a,(r_ownl)
        or a
        jr z,.n_opp
        ; the mover pocketed his last coin
        ld a,(r_pa)
        ld (rW),a
        ld a,(rQ)
        ld hl,rqp
        or (hl)
        ld hl,r_qcA
        or (hl)
        jr z,.n_o1
        call qc_a                ; 97, 52, 53b
        ld hl,r_b
        add a,(hl)
        jr .ret
.n_o1:  ld a,(r_qcB)
        or a
        jr z,.n_o2
        ld a,(r_b)               ; 53c
        jr .ret
.n_o2:  ld a,(r_pb)              ; 107a: last coin while the queen is on the board
        ld (rW),a
        call qv_b
        jr .ret
.n_opp: ; the mover pocketed the opponent's last coin
        ld a,(r_pb)
        ld (rW),a
        ld a,(rqp)
        ld hl,r_qon
        or (hl)
        ld hl,rQ
        or (hl)
        jr z,.n_p1
        call qc_b                ; 103a, 106a
        jr .n_p3
.n_p1:  ld a,(r_qcB)
        or a
        jr z,.n_p3
        call qc_b
.n_p3:  ld hl,r_a
        add a,(hl)
.ret:   ld (rP),a
        scf
        ret

; queen value for pair A/B: 3 points, or 1 from a score of 22 (ICF 102-112)
qv_a:   ld a,(r_pa)
        jr qv
qv_b:   ld a,(r_pb)
qv:     call pscore
        cp 22
        ld a,3
        ret c
        ld a,1
        ret
; queen credit: 3, or 0 from a score of 22 (ICF 52b, 54)
qc_a:   ld a,(r_pa)
        jr qc
qc_b:   ld a,(r_pb)
qc:     call pscore
        cp 22
        ld a,3
        ret c
        xor a
        ret
pscore: ld e,a
        ld d,0
        ld hl,game_score
        add hl,de
        ld a,(hl)
        ret

finish_board:
        call stats_board
        push af
        ld a,(rP)
        cp 13
        jr c,1F
        ld a,12                  ; ICF 55: at most 12 points a board
1:      ld (rP),a
        ld a,(rW)
        ld e,a
        ld d,0
        ld hl,game_score
        add hl,de
        ld a,(rP)
        add a,(hl)
        ld (hl),a
        ld hl,boards_won
        add hl,de
        inc (hl)
        ld a,(hl)
        cp 100
        jr nc,.stats_reset
        pop af
        call c,stats_clear
        jr .stats_done
.stats_reset:
        pop af
        call stats_clear
.stats_done:
        ld hl,boards_in_game
        inc (hl)
        xor a
        ld (dues),a
        ld (dues+1),a
        call msg_clear
        ld hl,S_BOARD
        call msg_s
        ld a,(boards_in_game)
        call msg_n
        ld hl,S_COLON
        call msg_s
        ld a,(rW)
        call msg_pair
        ld hl,S_WINS
        call msg_s
        ld a,(rP)
        call msg_n
        ld hl,S_PTS
        call msg_s
        call msg_show
        call render
        call hud
        ld hl,SONG_BOARD
        xor a
        call music_play
        ld a,120
        ld c,PH_AFTERBOARD
        jp wait_then

; ICF 56, 57: a game is 25 points or eight boards; best of three games
ph_afterboard:
        ld a,(game_score)
        cp 25
        jr nc,.g
        ld a,(game_score+1)
        cp 25
        jr nc,.g
        ld a,(boards_in_game)
        cp 8
        jr c,.nog
        ld a,(game_score)
        ld hl,game_score+1
        cp (hl)
        jr nz,.g
        ; ICF extra board after a tied eighth board: choose a fresh logical breaker.
        ld c,4
        call rand_n
        ld (extra_breaker),a
        ld a,1
        ld (extra_board),a
.nog:   ld a,PH_NEWBOARD
        ld (phase),a
        ret
.g:     ld a,(game_score)
        ld hl,game_score+1
        cp (hl)
        ld a,0
        jr nc,1F
        inc a
1:      ld (rA),a
        ld e,a
        ld d,0
        ld hl,games_won
        add hl,de
        inc (hl)
        ld a,(hl)
        cp 100
        call nc,stats_clear
        ld hl,games_played
        inc (hl)
        ld a,(rA)
        or a
        jr nz,2F
        ld hl,gw
        inc (hl)
2:      call msg_clear
        ld hl,S_GAMEOVER
        call msg_s
        ld a,(games_played)
        call msg_n
        ld hl,S_TO
        call msg_s
        ld a,(rA)
        call msg_pair
        ld a,' '
        call msg_c
        ld a,(game_score)
        call msg_n
        ld a,'-'
        call msg_c
        ld a,(game_score+1)
        call msg_n
        call msg_show
        call hud
        ld hl,SONG_GAME
        xor a
        call music_play
        ld a,150
        ld c,PH_AFTERGAME
        jp wait_then

ph_aftergame:
        ld a,(gw)
        cp 2
        jr nc,.m
        ld b,a
        ld a,(games_played)
        sub b
        cp 2
        jr nc,.m
        call rotate_players_right
        call new_game
        jp hud
.m:     call msg_clear
        ld hl,S_MATCH
        call msg_s
        ld a,(gw)
        cp 2
        ld a,0
        jr nc,1F
        inc a
1:      call msg_pair
        ld a,' '
        call msg_c
        ld a,(gw)
        call msg_n
        ld a,'-'
        call msg_c
        ld a,(games_played)
        ld hl,gw
        sub (hl)
        call msg_n
        ld hl,S_STARS
        call msg_s
        call msg_show
        ld hl,SONG_MATCH
        xor a
        call music_play
        ld a,150
        ld c,PH_NEWMATCH
        jp wait_then

; 66 bytes — Applies one coin colour's net pocket/return delta to its owning pair.
; A = colour, B = pocketed this stroke. rret[colour] supplies physical returns.
stats_colour:
        ld e,a
        ld d,0
        ld hl,rret
        add hl,de
        ld c,(hl)
        ld a,(white_pair)
        xor e
        ld e,a
        ld hl,score
        add hl,de
        ld a,c
        cp b
        ret z
        jr c,.add
        sub b
        ld c,a
        ld a,(hl)
        sub c
        jr nc,.store
        add a,100
        ld (hl),a
        inc hl
        inc hl
        ld a,(hl)
        or a
        jr z,.zero
        dec (hl)
        ret
.zero:  xor a
        dec hl
        dec hl
        ld (hl),a
        ret
.add:   ld a,b
        sub c
        ld c,a
        ld a,(hl)
        add a,c
        cp 100
        jr c,.store
        sub 100
        ld (hl),a
        inc hl
        inc hl
        inc (hl)
        ld a,(hl)
        cp 10
        ccf
        ret
.store: ld (hl),a
        or a
        ret

; 14 bytes — Wipes the public counters when one gets too ambitious.
stats_clear:
        xor a
        ld hl,score
        ld (hl),a
        ld de,score+1
        ld bc,7
        ldir
        ret

; ---------------------------------------------------------------- HUD
; 390 bytes — Keeps scores and status readable while the coins cause trouble.
; Each corner is 6 character cells = 12 columns of the 64-column font:
;   row 1   RED (o)x9 DUE       name, coin colour, coins left, dues owed
;   row 2   PTS 125 (Q)         session points (3 digits), queen covered
;   row 21  GAMES  2            games won (2 digits)
;   row 22  BOARDS12            boards won (2 digits)

hud:
        xor a
        call hud_pair
        ld a,1
hud_pair:
        ld (hp_p),a
        ld c,0
        or a
        jr z,1F
        ld c,52
1:      ld a,c
        ld (hp_col),a
        ld a,(hp_p)
        call pair_colour
        ld (hp_c),a
        ; row 1: name, coin colour, coins left, dues
        ld a,(hp_p)
        ld hl,S_RED
        or a
        jr z,2F
        ld hl,S_BLU
2:      ld de,0x0100
        call hud_s
        ld a,' '
        ld de,0x0103
        call hud_ch
        ld a,(hp_c)
        add a,128
        ld de,0x0104
        call hud_ch
        ld a,'x'
        ld de,0x0106
        call hud_ch
        ld a,(hp_c)
        ld e,a
        ld d,0
        ld hl,left
        add hl,de
        ld a,(hl)
        add a,'0'
        ld de,0x0107
        call hud_ch
        ld a,(hp_c)              ; dues outstanding
        ld e,a
        ld d,0
        ld hl,dues
        add hl,de
        ld a,(hl)
        or a
        ld hl,S_DUE
        jr nz,3F
        ld hl,S_NODUE
3:      ld de,0x0108
        call hud_s
        ; row 2: points, queen
        ld hl,S_HPTS
        ld de,0x0200
        call hud_s
        ld a,(hp_p)
        ld e,a
        ld d,0
        ld hl,score
        add hl,de
        ld a,(hl)
        push af
        inc hl
        inc hl
        ld a,(hl)
        or a
        jr z,6F
        add a,'0'
        jr 7F
6:      ld a,' '
7:      ld de,0x0204
        call hud_ch
        pop af
        ld de,0x0205
        call hud_num2
        ld a,' '
        ld de,0x0207
        call hud_ch
        ld a,(qstate)            ; queen covered by this side
        cp 2
        jr nz,4F
        ld a,(qcover)
        dec a
        ld hl,hp_c
        cp (hl)
        jr nz,4F
        ld a,130
        ld de,0x0208
        call hud_ch
        jr 5F
4:      ld hl,S_NODUE+2          ; two spaces
        ld de,0x0208
        call hud_s
5:      ld hl,S_NODUE+2
        ld de,0x020A
        call hud_s
        ; row 21: games won
        ld hl,S_HGAMES
        ld de,0x1500
        call hud_s
        ld a,(hp_p)
        ld e,a
        ld d,0
        ld hl,games_won
        add hl,de
        ld a,(hl)
        ld de,0x1507
        call hud_num2
        ld hl,S_NODUE+1
        ld de,0x1509
        call hud_s
        ; row 22: boards won
        ld hl,S_HBOARDS
        ld de,0x1600
        call hud_s
        ld a,(hp_p)
        ld e,a
        ld d,0
        ld hl,boards_won
        add hl,de
        ld a,(hl)
        ld de,0x1607
        call hud_num2
        ld hl,S_NODUE+1
        ld de,0x1609
        jp hud_s

; A = char at row D, column hp_col+E (64-column units)
hud_ch:
        ld b,d
        push af
        ld a,(hp_col)
        add a,e
        ld c,a
        pop af
        jp put64
; string HL at row D, column hp_col+E
hud_s:
        ld b,d
        ld a,(hp_col)
        add a,e
        ld c,a
        jp print64
; A (0-99) right-aligned in two columns at D,E
hud_num2:
        call num_digits
        ld a,(nd_d+1)
        jr hud_dig2
hud_dig2:
        call hud_dig
        inc e
        ld a,(nd_d+2)
hud_dig:
        push de
        call hud_ch
        pop de
        ret
; A -> nd_d: three digit characters, leading zeros as spaces (units always a digit)
num_digits:
        ld b,'0'-1
1:      inc b
        sub 100
        jr nc,1B
        add a,100
        ld c,'0'-1
2:      inc c
        sub 10
        jr nc,2B
        add a,10+'0'
        ld (nd_d+2),a
        ld a,b
        cp '0'
        jr nz,3F
        ld b,' '
        ld a,c
        cp '0'
        jr nz,3F
        ld c,' '
3:      ld a,b
        ld (nd_d),a
        ld a,c
        ld (nd_d+1),a
        ret

msg_profile:
        call logical_player
        add a,a
        ld l,a
        ld h,0
        ld de,PROFNAMES
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp msg_s

; ---------------------------------------------------------------- the Carrom Engine
; 2499 bytes — Chooses robot shots, scores options, and converts intent into velocity.
;
; Candidate generation (ghost-coin aiming at each pocket for every legal target), a cheap
; geometric check of both paths, then utility scoring with a per-player weighting profile:
;   player 0 AGGRESSIVE, 1 BALANCED, 2 DEFENSIVE, 3 TRICKSTER
; Coordinates are in the seat frame, in half pixels: u along the baseline, v forward.

; profile: wc, wd, cmin, qbonus(2), cutbonus, margin(/64), jitter(1/16 px)
PROFILES:
        db 8,2,18
        dw 300
        db 0,84,5
        db 8,2,22
        dw 120
        db 0,76,4
        db 12,1,26
        dw 60
        db 0,72,3
        db 5,2,14
        dw 160
        db 3,80,6
PF_WC   EQU 0
PF_WD   EQU 1
PF_CMIN EQU 2
PF_QB   EQU 3
PF_CUT  EQU 5
PF_MARG EQU 6
PF_JIT  EQU 7

ai_begin:
        ; profile follows logical player identity, not the physical chair
        call logical_player
        add a,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,PROFILES
        add hl,de
        ld de,pf
        ld bc,8
        ldir
        ; seat-frame coordinates of every coin
        ld ix,BODIES
        ld b,0
.lp:    push bc
        ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(ix+BF)
        and F_ON
        ld (hl),a
        jr z,.nx
        push de
        ld a,(ix+BX+1)
        sub 128
        sra a
        ld l,a
        rla
        sbc a,a
        ld h,a
        push hl
        ld a,(ix+BY+1)
        sub 96
        sra a
        ld e,a
        rla
        sbc a,a
        ld d,a
        pop hl
        call to_seat16
        ld a,l
        ld c,e
        pop de
        ld hl,ai_u
        add hl,de
        ld (hl),a
        ld hl,ai_v
        add hl,de
        ld (hl),c
.nx:    ld de,BSZ
        add ix,de
        pop bc
        inc b
        ld a,b
        cp 19
        jr c,.lp
        ; targets
        xor a
        ld (ai_tn),a
        ld (ai_k),a
        ld (ai_mode),a
        ld hl,-30000
        ld (ai_best),hl
        ld a,0xFF
        ld (ai_bid),a
        ld a,(break_made)
        or a
        jr nz,1F
        ld a,1
        ld (ai_mode),a           ; the break
        ret
1:      call mover_colour
        ld (ai_col),a
        ld b,a
        add a,a
        add a,a
        add a,a
        add a,b
        ld c,a                   ; first id of my colour
        ld b,9
.t:     push bc
        ld e,c
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        call nz,ai_addt
        pop bc
        inc c
        djnz .t
        ; the queen, when he has the right to her (ICF 92, 95)
        ld a,(ai_on+QUEEN)
        or a
        ret z
        ld a,(qstate)
        or a
        ret nz
        ld a,(ai_col)
        ld e,a
        ld d,0
        ld hl,had
        add hl,de
        ld a,(hl)
        or a
        ret z
        ld hl,dues
        add hl,de
        ld a,(hl)
        or a
        ret nz
        ld c,QUEEN
ai_addt:
        ld a,(ai_tn)
        ld e,a
        ld d,0
        ld hl,ai_t
        add hl,de
        ld (hl),c
        inc a
        ld (ai_tn),a
        ret

; evaluate one (target, pocket) candidate; carry when every candidate is done
ai_step:
        ld a,(ai_mode)
        or a
        scf
        ret nz
        ld a,(ai_tn)
        add a,a
        add a,a
        ld b,a
        ld a,(ai_k)
        cp b
        ccf
        ret c
        call ai_eval
        ld hl,ai_k
        inc (hl)
        or a
        ret

ai_eval:
        ld a,(ai_k)
        ld b,a
        srl a
        srl a
        ld e,a
        ld d,0
        ld hl,ai_t
        add hl,de
        ld a,(hl)
        ld (ev_id),a
        ld a,b
        and 3
        ld (ev_p),a
        ld c,-34
        bit 0,a
        jr z,1F
        ld c,34
1:      ld b,-34
        bit 1,a
        jr z,2F
        ld b,34
2:      ld a,c
        ld (ev_pu),a
        ld a,b
        ld (ev_pv),a
        ld a,(ev_id)
        ld e,a
        ld d,0
        ld hl,ai_u
        add hl,de
        ld a,(hl)
        ld (ev_cu),a
        ld hl,ai_v
        add hl,de
        ld a,(hl)
        ld (ev_cv),a
        ; coin -> pocket
        ld a,(ev_cu)
        ld b,a
        ld a,(ev_pu)
        sub b
        ld (ev_dx),a
        ld a,(ev_cv)
        ld b,a
        ld a,(ev_pv)
        sub b
        ld (ev_dy),a
        ld a,(ev_dx)
        ld b,a
        ld a,(ev_dy)
        ld c,a
        call len8
        cp 3
        ret c
        ld (ev_lcp),a
        ld a,(ev_cu)
        ld (sg_au),a
        ld a,(ev_cv)
        ld (sg_av),a
        ld a,(ev_pu)
        ld (sg_bu),a
        ld a,(ev_pv)
        ld (sg_bv),a
        ld a,8
        ld (sg_d),a
        ld a,(ev_id)
        ld (sg_skip),a
        call seg_blocked
        ret c
        ; unit vector coin -> pocket (x64)
        ld a,(ev_lcp)
        ld (dv_len),a
        ld a,(ev_dx)
        call div64
        ld (ev_nx),a
        ld a,(ev_dy)
        call div64
        ld (ev_ny),a
        ; ghost position: the striker's centre at contact, 9 px behind the coin
        ld a,(ev_nx)
        ld b,a
        ld c,9
        call smul8
        call sra7
        ld a,(ev_cu)
        sub l
        ld (ev_gu),a
        ld a,(ev_ny)
        ld b,a
        ld c,9
        call smul8
        call sra7
        ld a,(ev_cv)
        sub l
        ld (ev_gv),a
        ; striker placements to try
        ld a,(ev_pv)
        ld b,a
        ld a,(ev_cv)
        cp b
        jp p,.back
        ; the pocket is ahead: straight-on placement, where the pocket-coin line meets the baseline
        ld a,(ev_dx)
        ld b,a
        ld a,(ev_cv)
        sub VB_HALF
        ld c,a
        call smul8
        ld a,(ev_dy)
        ld c,a
        ld a,h
        ld (sd_sign),a
        call abshl
        call div16_8
        ld a,(sd_sign)
        bit 7,a
        call nz,neghl
        ; Su = Cu - HL  (clamped to +-28 by ai_place)
        ex de,hl
        ld a,(ev_cu)
        ld l,a
        rla
        sbc a,a
        ld h,a
        or a
        sbc hl,de
        call clamp28
        ld (ev_s0),a
        call ai_place
        ld a,(ev_s0)
        add a,6
        call ai_place
        ld a,(ev_s0)
        sub 6
        jp ai_place
.back:  ; the pocket is behind the coin: cut it back from the far side
        ld a,(ev_dx)
        or a
        ld b,24
        jp m,3F
        ld b,-24
3:      ld a,(ev_cu)
        add a,b
        ld l,a
        rla
        sbc a,a
        ld h,a
        call clamp28
        call ai_place
        ld a,(ev_dx)
        or a
        ld b,12
        jp m,4F
        ld b,-12
4:      ld a,(ev_cu)
        add a,b
        ld l,a
        rla
        sbc a,a
        ld h,a
        call clamp28
        jp ai_place

; HL signed -> A clamped to -28..28
clamp28:
        ld de,28
        bit 7,h
        jr nz,1F
        push hl
        or a
        sbc hl,de
        pop hl
        ld a,l
        ret c
        ld a,28
        ret
1:      push hl
        add hl,de
        pop hl
        ld a,l
        ret c
        ld a,-28
        ret

sra7:   ld b,7
        jr 1F
sra6:   ld b,6
1:      sra h
        rr l
        djnz 1B
        ret

; A = round-down sqrt(B*B + C*C), signed B, C
len8:
        ld a,b
        or a
        jp p,1F
        neg
1:      ld b,a
        ld a,c
        or a
        jp p,2F
        neg
2:      push af
        ld c,b
        call mul8u
        pop af
        push hl
        ld b,a
        ld c,a
        call mul8u
        pop de
        add hl,de
        jp isqrt16

; A = A*64/dv_len (signed)
div64:
        ld (sd_sign),a
        or a
        jp p,1F
        neg
1:      ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(dv_len)
        ld c,a
        call div16_8
        ld a,(sd_sign)
        bit 7,a
        ld a,l
        ret z
        neg
        ret

; try the striker at u = A (half pixels) on the baseline against the current candidate
ai_place:
        cp 29
        jr c,1F
        cp -28&255
        ret c
1:      ld (ev_su),a
        call strike_legal
        ret c
        ; toward the ghost, forward only
        ld a,(ev_su)
        ld b,a
        ld a,(ev_gu)
        sub b
        ld (ev_ux),a
        ld a,(ev_gv)
        sub VB_HALF
        ld (ev_uy),a
        cp 3
        ret c
        cp 100
        ret nc
        cp 32
        jr nc,2F
        add a,a
        add a,a
        ld c,a                   ; 4*gv: at least 14 degrees off the baseline
        ld a,(ev_ux)
        or a
        jp p,1F
        neg
1:      cp c
        ret nc
2:
        ld a,(ev_ux)
        ld b,a
        ld a,(ev_uy)
        ld c,a
        call len8
        or a
        ret z
        ld (ev_lsg),a
        ld (dv_len),a
        ld a,(ev_ux)
        call div64
        ld (ev_ux),a
        ld a,(ev_uy)
        call div64
        ld (ev_uy),a
        ; cut: cos between the striker's path and the coin's path (x64)
        ld a,(ev_ux)
        ld b,a
        ld a,(ev_nx)
        ld c,a
        call smul8
        push hl
        ld a,(ev_uy)
        ld b,a
        ld a,(ev_ny)
        ld c,a
        call smul8
        pop de
        add hl,de
        call sra6
        bit 7,h
        ret nz
        ld a,(pf+PF_CMIN)
        ld b,a
        ld a,l
        cp b
        ret c
        ld (ev_c64),a
        ; the striker's path must be clear
        ld a,(ev_su)
        ld (sg_au),a
        ld a,VB_HALF
        ld (sg_av),a
        ld a,(ev_gu)
        ld (sg_bu),a
        ld a,(ev_gv)
        ld (sg_bv),a
        ld a,9
        ld (sg_d),a
        ld a,(ev_id)
        ld (sg_skip),a
        call seg_blocked
        ret c
        ; utility
        ld a,(ev_c64)
        ld b,a
        ld a,(pf+PF_WC)
        ld c,a
        call mul8u
        push hl
        ld a,(ev_lsg)
        ld b,a
        ld a,(ev_lcp)
        add a,b
        ld b,a
        ld a,(pf+PF_WD)
        ld c,a
        call mul8u
        ex de,hl
        pop hl
        or a
        sbc hl,de
        ld a,(ev_id)
        cp QUEEN
        jr nz,5F
        ld de,(pf+PF_QB)
        add hl,de
5:      ld a,(pf+PF_CUT)
        or a
        jr z,6F
        push hl
        ld b,a
        ld a,(ev_c64)
        ld c,a
        ld a,64
        sub c
        ld c,a
        call mul8u
        ex de,hl
        pop hl
        add hl,de
6:      push hl
        call rand
        ld a,l
        and 7
        pop hl
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ; better than the best so far?
        ld de,(ai_best)
        push hl
        or a
        sbc hl,de
        pop hl
        ret z
        ret m
        ld (ai_best),hl
        ld a,(ev_id)
        ld (ai_bid),a
        ld a,(ev_p)
        ld (ai_bp),a
        ld a,(ev_su)
        ld (ai_bsu),a
        ld a,(ev_c64)
        ld (ai_bc64),a
8:      ret

; carry if a coin lies on the path A->B within sg_d pixels (half-pixel coordinates)
seg_blocked:
        ld a,(sg_au)
        ld b,a
        ld a,(sg_bu)
        sub b
        ld (sg_ex),a
        ld a,(sg_av)
        ld b,a
        ld a,(sg_bv)
        sub b
        ld (sg_ey),a
        ld a,(sg_ex)
        ld b,a
        ld a,(sg_ey)
        ld c,a
        call len8
        ld (sg_l),a
        ld b,a
        ld c,a
        call mul8u
        ld (sg_l2),hl
        ld a,(sg_l)
        ld b,a
        ld a,(sg_d)
        ld c,a
        call mul8u
        ld (sg_dl),hl
        ld a,(sg_d)
        ld b,a
        ld c,a
        call mul8u
        srl h
        rr l
        srl h
        rr l
        ld (sg_dq),hl
        ; bounding box (biased by 0x80 for unsigned compares)
        ld a,(sg_au)
        ld b,a
        ld a,(sg_bu)
        call minmax
        ld (sg_umin),bc
        ld a,(sg_av)
        ld b,a
        ld a,(sg_bv)
        call minmax
        ld (sg_vmin),bc
        ld b,0
.lp:    push bc
        ld a,(sg_skip)
        cp b
        jp z,.nx
        ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        jp z,.nx
        ld hl,ai_u
        add hl,de
        ld a,(hl)
        ld (sg_ou),a
        xor 0x80
        ld hl,sg_umin
        cp (hl)
        jp c,.nx
        inc hl
        cp (hl)
        jr z,1F
        jp nc,.nx
1:      ld hl,ai_v
        add hl,de
        ld a,(hl)
        ld (sg_ov),a
        xor 0x80
        ld hl,sg_vmin
        cp (hl)
        jp c,.nx
        inc hl
        cp (hl)
        jr z,2F
        jp nc,.nx
2:      ; o = O - A
        ld a,(sg_au)
        ld b,a
        ld a,(sg_ou)
        sub b
        ld (sg_ox),a
        ld a,(sg_av)
        ld b,a
        ld a,(sg_ov)
        sub b
        ld (sg_oy),a
        ; dot = e.o
        ld a,(sg_ex)
        ld b,a
        ld a,(sg_ox)
        ld c,a
        call smul8
        push hl
        ld a,(sg_ey)
        ld b,a
        ld a,(sg_oy)
        ld c,a
        call smul8
        pop de
        add hl,de
        bit 7,h
        jr nz,.nx                ; behind the start
        ld de,(sg_l2)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.mid
        jr z,.mid
        ld a,(sg_noend)
        or a
        jr nz,.nx
        ; beyond the end: blocked if it touches the end point
        ld a,(sg_bu)
        ld b,a
        ld a,(sg_ou)
        sub b
        ld b,a
        ld a,(sg_bv)
        ld c,a
        ld a,(sg_ov)
        sub c
        ld c,a
        call len8
        ld b,a
        ld c,a
        call mul8u
        ld de,(sg_dq)
        or a
        sbc hl,de
        jr c,.blk
        jr .nx
.mid:   ; perpendicular distance: |cross| / L < d/2  <=>  2|cross| < d*L
        ld a,(sg_ex)
        ld b,a
        ld a,(sg_oy)
        ld c,a
        call smul8
        push hl
        ld a,(sg_ey)
        ld b,a
        ld a,(sg_ox)
        ld c,a
        call smul8
        ex de,hl
        pop hl
        or a
        sbc hl,de
        call abshl
        add hl,hl
        ld de,(sg_dl)
        or a
        sbc hl,de
        jr c,.blk
.nx:    pop bc
        inc b
        ld a,b
        cp 19
        jp c,.lp
        or a
        ret
.blk:   pop bc
        scf
        ret

; B, A signed -> C = min-5, B = max+5 (both biased by 0x80): stored as (min,max)
minmax:
        xor 0x80
        ld c,a
        ld a,b
        xor 0x80
        ld b,a
        cp c
        jr c,1F
        ld a,c                   ; c <= b
        ld c,b
        ld b,a
1:      ; now b = min, c = max
        ld a,b
        sub 5
        jr nc,2F
        xor a
2:      ld b,a
        ld a,c
        add a,5
        jr nc,3F
        ld a,255
3:      ld c,a
        ld a,b
        ld b,c
        ld c,a
        ret

; ---- turning the chosen candidate into a stroke

ai_finish:
        ld a,(ai_mode)
        or a
        jp nz,plan_break
        ld a,(ai_bid)
        cp 0xFF
        jp z,plan_fallback
        ld a,(ai_bsu)
        add a,a
        ld (plan_u),a
        call place_xy
        ; coin centre in 1/16 px
        ld a,(ai_bid)
        call body_ptr
        call body16
        ld (fc_cx),hl
        ld (fc_cy),de
        ; pocket centre in screen pixels
        ld a,(ai_bp)
        ld hl,-68
        bit 0,a
        jr z,1F
        ld hl,68
1:      ld de,-68
        bit 1,a
        jr z,2F
        ld de,68
2:      call from_seat16
        ld bc,128
        add hl,bc
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld (fc_px),hl
        ex de,hl
        ld bc,96
        add hl,bc
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld (fc_py),hl
        ; coin -> pocket
        ld de,(fc_cx)
        ld hl,(fc_px)
        or a
        sbc hl,de
        ld (fc_dx),hl
        ld hl,(fc_py)
        ld de,(fc_cy)
        or a
        sbc hl,de
        ld (fc_dy),hl
        ld hl,(fc_dx)
        ld de,(fc_dy)
        call len16
        ld (fc_lcp),hl
        ; ghost = coin - 9 px along that line
        ld hl,(fc_dx)
        call ghost_off
        ex de,hl
        ld hl,(fc_cx)
        or a
        sbc hl,de
        ld (fc_gx),hl
        ld hl,(fc_dy)
        call ghost_off
        ex de,hl
        ld hl,(fc_cy)
        or a
        sbc hl,de
        ld (fc_gy),hl
        call jitter
        ; speed: the coin must arrive with ARRIVE to spare; the striker loses c in the cut
        ld bc,ACC
        ld de,(fc_lcp)
        call mul16u
        ld d,e
        ld e,h
        ld h,l
        ld l,0
        call isqrt32
        ld de,600
        add hl,de
        ld b,h
        ld c,l
        ld de,54
        call mul16u
        ld a,(ai_bc64)
        ld c,a
        ld b,0
        call div32_16
        ld de,15000
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,3F
        ex de,hl
3:      ld (fc_vc),hl
        ; striker path length
        call dir_to_target
        ; v^2 = vc^2 + 2 a d
        ld bc,(fc_vc)
        ld d,b
        ld e,c
        call mul16u
        ld (fc_t),hl
        ld (fc_t+2),de
        ld bc,ACC
        ld de,(fc_lsg)
        call mul16u
        ld d,e
        ld e,h
        ld h,l
        ld l,0
        ld bc,(fc_t)
        add hl,bc
        ex de,hl
        ld bc,(fc_t+2)
        adc hl,bc
        ex de,hl
        call isqrt32
        ld a,(pf+PF_MARG)
        call mul16x8u
        ld b,6
        call sra24
        or a
        jr z,4F
        ld hl,VMAX
4:      ld de,VMAX
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,5F
        ex de,hl
5:      jp set_velocity

; DE:HL helpers ---------------------------------------------------
; body IX centre in 1/16 px: HL = x, DE = y
body16:
        ld l,(ix+BX)
        ld h,(ix+BX+1)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        push hl
        ld l,(ix+BY)
        ld h,(ix+BY+1)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ex de,hl
        pop hl
        ret

; HL = sqrt(HL^2 + DE^2) for signed 16-bit HL, DE (|v| < 4096)
len16:
        push de
        call abshl
        ld b,h
        ld c,l
        ld d,h
        ld e,l
        call mul16u
        ld (ln_t),hl
        ld (ln_t+2),de
        pop hl
        call abshl
        ld b,h
        ld c,l
        ld d,h
        ld e,l
        call mul16u
        ld bc,(ln_t)
        add hl,bc
        ex de,hl
        ld bc,(ln_t+2)
        adc hl,bc
        ex de,hl
        jp isqrt32

; HL = (component * 144) / lcp, signed   (9 px in 1/16 px along the unit vector)
ghost_off:
        ld a,h
        ld (sd_sign),a
        call abshl
        ex de,hl
        ld bc,144
        call mul16u
        ld bc,(fc_lcp)
        call div32_16
        ld a,(sd_sign)
        bit 7,a
        ret z
        jp neghl

; small random error on the aim point, per profile
jitter:
        ld a,(pf+PF_JIT)
        add a,a
        inc a
        ld c,a
        call rand_n
        ld b,a
        ld a,(pf+PF_JIT)
        ld c,a
        ld a,b
        sub c
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(fc_gx)
        add hl,de
        ld (fc_gx),hl
        ld a,(pf+PF_JIT)
        add a,a
        inc a
        ld c,a
        call rand_n
        ld b,a
        ld a,(pf+PF_JIT)
        ld c,a
        ld a,b
        sub c
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(fc_gy)
        add hl,de
        ld (fc_gy),hl
        ret

; striker placement (plan_u, baseline) -> fc_sx, fc_sy in 1/16 px
place_xy:
        ld a,(plan_u)
        ld l,a
        rla
        sbc a,a
        ld h,a
        ld de,-66
        call from_seat16
        ld bc,128
        add hl,bc
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld (fc_sx),hl
        ex de,hl
        ld bc,96
        add hl,bc
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld (fc_sy),hl
        ret

; fc_g - fc_s -> fc_ux, fc_uy, fc_lsg
dir_to_target:
        ld hl,(fc_gx)
        ld de,(fc_sx)
        or a
        sbc hl,de
        ld (fc_ux),hl
        ld hl,(fc_gy)
        ld de,(fc_sy)
        or a
        sbc hl,de
        ld (fc_uy),hl
        ld hl,(fc_ux)
        ld de,(fc_uy)
        call len16
        ld a,h
        or l
        jr nz,1F
        inc hl
1:      ld (fc_lsg),hl
        ret

; HL = speed: velocity along fc_u, aim-line step, plan
set_velocity:
        ld (plan_speed),hl
        ld hl,(fc_ux)
        call vcomp
        ld (plan_vx),hl
        ld hl,(fc_uy)
        call vcomp
        ld (plan_vy),hl
        ; aim line step = unit vector in 8.8
        ld hl,(fc_ux)
        call ucomp
        ld (aim_sx),hl
        ld hl,(fc_uy)
        call ucomp
        ld (aim_sy),hl
        or a                     ; every committed plan returns with carry clear
        ret
vcomp:  ld a,h
        ld (sd_sign),a
        call abshl
        ex de,hl
        ld bc,(plan_speed)
        call mul16u
        ld bc,(fc_lsg)
        call div32_16
        ld a,(sd_sign)
        bit 7,a
        ret z
        jp neghl
ucomp:  ld a,h
        ld (sd_sign),a
        call abshl
        ex de,hl
        ld bc,256
        call mul16u
        ld bc,(fc_lsg)
        call div32_16
        ld a,(sd_sign)
        bit 7,a
        ret z
        jp neghl

; the break: from near the middle of the baseline, hard into the formation
plan_break:
        ld c,13
        call rand_n
        sub 6
        add a,a
        ld (plan_u),a
        call place_xy
        ld hl,128*16
        ld (fc_gx),hl
        ld hl,96*16
        ld (fc_gy),hl
        call jitter
        call dir_to_target
        ld hl,11800
        jp set_velocity

; no pocketing chance: play a firm stroke straight at the nearest coin of his own colour
; (a "safety"), or at any coin, or failing all that up the middle
plan_fallback:
        xor a
        ld (fb_tier),a
.tier:  ld hl,30000
        ld (fb_best),hl
        ld a,0xFF
        ld (fb_id),a
        ld b,0
.lp:    push bc
        ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        jr z,.nx
        ld a,b
        cp QUEEN
        jr z,.nx
        ld a,b
        cp 9
        ccf
        ld a,0
        adc a,0
        ld hl,ai_col
        cp (hl)
        ld c,0
        jr z,1F
        ld c,40                  ; prefer my own colour
1:      ld a,c
        ld (fb_pen),a
        ld a,b
        ld (ev_id),a
        ld hl,ai_u
        add hl,de
        ld a,(hl)
        ld (ev_gu),a
        ld hl,ai_v
        add hl,de
        ld a,(hl)
        ld (ev_gv),a
        ld a,(ev_gu)
        call fb_try
        xor a
        call fb_try
        ld a,20
        call fb_try
        ld a,-20
        call fb_try
.nx:    pop bc
        inc b
        ld a,b
        cp 19
        jr c,.lp
        ld a,(fb_id)
        cp 0xFF
        jr nz,.hit
        ld a,(fb_tier)          ; nothing with a clear path: just hit the nearest coin
        or a
        jr nz,.mid
        inc a
        ld (fb_tier),a
        jp .tier
.mid:   call fallback_legal
        ret c                    ; every legal baseline point was blocked
        call place_xy
        ld hl,128*16
        ld (fc_gx),hl
        ld hl,96*16
        ld (fc_gy),hl
        jr .go
.hit:   ld a,(fb_su)
        add a,a
        ld (plan_u),a
        call place_xy
        ld a,(fb_id)
        call body_ptr
        call body16
        ld (fc_gx),hl
        ld (fc_gy),de
.go:    call dir_to_target
        ld hl,6800
        jp set_velocity

fb_try:
        call clamp_a28
        ld (ev_su),a
        ; forward and clear?
        ld b,a
        ld a,(ev_gu)
        sub b
        ld (ev_ux),a
        ld a,(ev_gv)
        sub VB_HALF
        cp 6
        ret c
        ld (ev_uy),a
        cp 32
        jr nc,2F
        add a,a
        add a,a
        ld c,a
        ld a,(ev_ux)
        or a
        jp p,1F
        neg
1:      cp c
        ret nc
2:      ld a,(ev_su)
        call strike_legal
        ret c
        ld a,(fb_tier)
        or a
        jr nz,3F
        ld a,(ev_su)
        ld (sg_au),a
        ld a,VB_HALF
        ld (sg_av),a
        ld a,(ev_gu)
        ld (sg_bu),a
        ld a,(ev_gv)
        ld (sg_bv),a
        ld a,9
        ld (sg_d),a
        ld a,(ev_id)
        ld (sg_skip),a
        ld a,1
        ld (sg_noend),a
        call seg_blocked
        ld a,0
        ld (sg_noend),a
        ret c
3:      ld a,(ev_ux)
        ld b,a
        ld a,(ev_uy)
        ld c,a
        call len8
        ld hl,fb_pen
        add a,(hl)
        ld l,a
        ld h,0
        ld de,(fb_best)
        push hl
        or a
        sbc hl,de
        pop hl
        ret nc
        ld (fb_best),hl
        ld a,(ev_id)
        ld (fb_id),a
        ld a,(ev_su)
        ld (fb_su),a
        ret

clamp_a28:
        ld l,a
        rla
        sbc a,a
        ld h,a
        jp clamp28

; carry if the striker at u = A (half px) on the baseline would touch a coin
strike_legal:
        ld (lg_su),a
        ld b,0
.lg:    ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        jr z,.n
        ld hl,ai_v
        add hl,de
        ld a,(hl)
        sub VB_HALF
        add a,5
        cp 10
        jr nc,.n
        sub 5
        ld (lg_dv),a
        ld hl,ai_u
        add hl,de
        ld a,(lg_su)
        ld c,a
        ld a,(hl)
        sub c
        add a,5
        cp 10
        jr nc,.n
        sub 5
        push bc
        call sq8
        push hl
        ld a,(lg_dv)
        call sq8
        pop de
        add hl,de
        pop bc
        ld de,21
        or a
        sbc hl,de
        ret c
.n:     inc b
        ld a,b
        cp 19
        jr c,.lg
        or a
        ret

; HL = A*A (A signed)
sq8:    or a
        jp p,1F
        neg
1:      ld b,a
        ld c,a
        jp mul8u
