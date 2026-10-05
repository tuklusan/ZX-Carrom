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

; 40 bytes total — Dispatches each frame to the right phase with minimal ceremony.
; 16 bytes — Dispatches the current phase through the compact phase table.
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
; 505 bytes total — Starts matches, boards, and turns without asking for a committee.

; 21 bytes — Resets the player map and tosses the first breaker for a fresh match.
new_match:
        call reset_player_map
        call record_progress
        xor a
        ld (games_played),a
        ld (gw),a
        ld c,4
        call rand_n
        ld (break_off),a        ; the toss: which seat breaks the first board
; 22 bytes — Clears game-local scores and schedules the first board.
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

; 2 bytes — Tail-jumps into match setup; even two bytes can have a job title.
ph_newmatch:
        jr new_match

; 19 bytes — Counts down a quiet inter-phase pause while the striker glides home.
ph_wait:
        call striker_glide
        ld hl,timer
        ld a,(hl)
        or a
        jr z,__N_game_1_0
        dec (hl)
        ret
__N_game_1_0:      ld a,(next_phase)
        ld (phase),a
        ret

; 13 bytes — Arms a timed pause and remembers which phase should wake up next.
wait_then:      ; A = frames, C = next phase
        ld (timer),a
        ld a,c
        ld (next_phase),a
        ld a,PH_WAIT
        ld (phase),a
        ret

; 63 bytes — Builds, renders, labels, and briefly presents a newly arranged board.
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

; 238 bytes — Resets every coin, queen, due, break, and striker detail for a clean board.
setup_board:
        call reset_board_pixels
        ; ICF extra board: a tied eighth board gets a fresh logical breaker toss.
        ; Normal boards keep the ordinary ICF 49 rotation and ignore stale toss data.
        ld a,(extra_board)
        or a
        jr z,__D_game_9_setup_board_normal_breaker
        xor a
        ld (extra_board),a      ; consume the one-shot extra-board selection
        ld a,(extra_breaker)
        and 3
        jr __D_game_9_setup_board_breaker_ready
__D_game_9_setup_board_normal_breaker:
        ld a,(boards_in_game)
        ld hl,games_played
        add a,(hl)
        ld hl,break_off
        add a,(hl)
        and 3
__D_game_9_setup_board_breaker_ready:
        ld c,a
        and 1
        ld (white_pair),a       ; the breaker's logical pair plays white (ICF 43)
        ld a,c
        call seat_for_player
        jr nc,__D_game_9_setup_board_seat_ok
        ; If the seat map goes feral, do not let a nonsense physical seat escape.
        ; Reset to the fresh-match map; direct callers still get carry as the warning light.
        call reset_player_map
        ld a,c
__D_game_9_setup_board_seat_ok:
        ld (seat),a
        ld ix,BODIES
        ld b,0
__D_game_9_setup_board_lp:    ld (ix+BID),b
        ld a,b
        ld c,0
        cp 9
        jr c,__N_game_1_1
        ld c,1
        cp 18
        jr c,__N_game_1_1
        ld c,2
        jr z,__N_game_1_1
        ld c,3
__N_game_1_1:      ld (ix+BK),c
        ld (ix+BR),4
        ld a,c
        cp 3
        jr nz,__N_game_2_0
        ld (ix+BR),5
__N_game_2_0:      call body_stop
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
        jr c,__D_game_9_setup_board_lp
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
__D_game_9_setup_board_f:     ld e,(hl)
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
        djnz __D_game_9_setup_board_f
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
; 15 bytes — Restores logical players to the four physical seats in plain order.
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
; 11 bytes — Maps one physical seat to its logical player, keeping geometry and identity apart.
logical_for_seat:
        and 3
        ld e,a
        ld d,0
        ld hl,player_at_seat
        add hl,de
        ld a,(hl)
        ret

; current mover's logical player
; 6 bytes — Maps the current physical seat to the mover's logical identity.
logical_player:
        ld a,(seat)
        jp logical_for_seat

; current mover's logical pair (0 = players 0/2, 1 = players 1/3)
; 6 bytes — Reduces the current logical player to doubles pair zero or one.
mover_pair:
        call logical_player
        and 1
        ret

; A = logical player -> A = physical seat, carry set and A=$FF if absent.
; Exactly four entries are examined so a damaged map cannot spin forever.
; 22 bytes — Searches the four-seat permutation for one logical player.
seat_for_player:
        ld c,a
        ld hl,player_at_seat
        ld b,4
        xor a
__N_game_1_2:      ld e,a
        ld a,(hl)
        cp c
        ld a,e
        jr z,__N_game_2_1
        inc hl
        inc a
        djnz __N_game_1_2
        scf
        sbc a,a
        ret
__N_game_2_1:      or a                    ; clear carry on success
        ret

; Carry clear only when all four logical players occur exactly once.
; With four slots, finding 0,1,2,3 proves there can be no duplicate or stray value.
; 15 bytes — Proves all four logical players occur exactly once before trusting the map.
validate_player_map:
        xor a
__N_game_1_3:      ld b,a
        push bc
        call seat_for_player
        pop bc
        ret c
        ld a,b
        inc a
        cp 4
        jr c,__N_game_1_3
        ret

; Every logical player moves one physical seat clockwise between games.
; Corrupt input is rejected with carry set, recovered to identity, then rotated.
; 43 bytes — Moves every logical player one physical seat clockwise between games.
rotate_players_right:
        call validate_player_map
        ld c,0
        jr nc,__D_game_16_rotate_players_right_rotate
        call reset_player_map
        ld c,1
__D_game_16_rotate_players_right_rotate:
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
; 3 bytes — Asks which coin colour belongs to the side currently moving.
mover_colour:
        call mover_pair
; 6 bytes — Combines pair identity with the white-pair assignment to get coin colour.
pair_colour:            ; A = logical pair -> A = colour
        ld b,a
        ld a,(white_pair)
        xor b
        ret

; ---------------------------------------------------------------- thinking
; 623 bytes total — Places, aims, and animates a shot while the robots look thoughtful.

; 61 bytes — Starts robot thinking, centres the striker, and opens the planning notebook.
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

; 60 bytes — Sweeps the striker baseline while the planner works a little each frame.
ph_think:
        ; rule 5, no cheating: the striker gets the whole baseline while the robot thinks
        ld a,(osc_d)
        ld b,a
        ld a,(osc_u)
        add a,b
        ld (osc_u),a
        cp 56
        jr z,__N_game_1_4
        cp -56 AND 255
        jr nz,__N_game_2_2
__N_game_1_4:      ld a,(osc_d)
        neg
        ld (osc_d),a
__N_game_2_2:      ld a,(osc_u)
        call set_striker_u
        ld hl,timer
        ld a,(hl)
        or a
        jr z,__N_game_3_0
        dec (hl)
__N_game_3_0:      call ai_step
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
; 30 bytes — Converts baseline offset into board coordinates for the current seat.
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
; 30 bytes — Rotates board coordinates into the current seat's local frame.
to_seat16:
        ld a,(seat)
        or a
        jr z,__D_game_22_to_seat16_n
        dec a
        jr z,__D_game_22_to_seat16_e
        dec a
        jr z,__D_game_22_to_seat16_s
        ex de,hl            ; W: u=-by v=bx
        jp neghl
__D_game_22_to_seat16_n:     jp neghl            ; N: u=-bx v=by
__D_game_22_to_seat16_e:     call neghl          ; E: u=by v=-bx
        ex de,hl
        ret
__D_game_22_to_seat16_s:     ex de,hl            ; S: u=bx v=-by
        call neghl
        ex de,hl
        ret
; HL=u DE=v -> HL=bx DE=by
; 30 bytes — Rotates local seat coordinates back into board coordinates.
from_seat16:
        ld a,(seat)
        or a
        jr z,__D_game_23_from_seat16_n
        dec a
        jr z,__D_game_23_from_seat16_e
        dec a
        jr z,__D_game_23_from_seat16_s
        call neghl          ; W: bx=v by=-u
        ex de,hl
        ret
__D_game_23_from_seat16_n:     jp neghl            ; N: bx=-u by=v
__D_game_23_from_seat16_e:     ex de,hl            ; E: bx=-v by=u
        jp neghl
__D_game_23_from_seat16_s:     ex de,hl            ; S: bx=u by=-v
        call neghl
        ex de,hl
        ret

; 100 bytes — Animates the striker from its thinking sweep to the chosen legal placement.
ph_place:
        ld a,(plan_u)
        ld b,a
        ld a,(osc_u)
        sub b
        jr z,__D_game_24_ph_place_there
        jp p,__D_game_24_ph_place_pos
        cp -2 AND 255
        jr nc,__D_game_24_ph_place_there
        ld a,(osc_u)
        add a,2
        jr __D_game_24_ph_place_set
__D_game_24_ph_place_pos:   cp 3
        jr c,__D_game_24_ph_place_there
        ld a,(osc_u)
        sub 2
__D_game_24_ph_place_set:   ld (osc_u),a
        jp set_striker_u
__D_game_24_ph_place_there: ld a,(plan_u)
        ld (osc_u),a
        call set_striker_u
        call render
        ; rule 2: keep the "Striker placed at (x,y) - striking in 1s" message exactly like this
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

; 41 bytes — Holds the placed striker briefly so humans can see what the robot decided.
ph_hold:
        ld a,(timer)
        or a
        jr z,__D_game_25_ph_hold_go
        and 7
        call z,halo_xor
        ld hl,timer
        dec (hl)
        ret
__D_game_25_ph_hold_go:    ; aim preview: the line grows from the striker to its strike-force length over 2 s
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

; 28 bytes — XORs the placement halo around the striker, subtle as a tiny disco ring.
halo_xor:
        ld hl,HALO
__D_game_26_halo_xor_lp:    ld a,(hl)
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
        jr __D_game_26_halo_xor_lp

; 26 bytes — Erases the previous aim preview and resets its drawing state.
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
__N_game_1_5:      push bc
        call aim_adv
        pop bc
        djnz __N_game_1_5
        ret
; 23 bytes — Advances the aim preview by one segment toward full strike length.
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
; 34 bytes — Plots one aim-preview point after rotating it into board space.
aim_plot:
        ld a,(aim_x+1)
        cp 57
        jr c,__D_game_29_aim_plot_out
        cp 199
        jr nc,__D_game_29_aim_plot_out
        ld b,a
        ld a,(aim_y+1)
        cp 25
        jr c,__D_game_29_aim_plot_out
        cp 167
        jr nc,__D_game_29_aim_plot_out
        ld c,a
        call plot_xor
        call aim_adv
        or a
        ret
__D_game_29_aim_plot_out:   scf
        ret

; 115 bytes — Animates the full aim line, then converts the plan into an actual strike.
ph_aim:
        ld hl,aim_t
        inc (hl)
        ld a,(hl)
        cp 100
        jr nc,__D_game_30_ph_aim_full
        ; target points = len * t / 100
        ld b,a
        ld a,(aim_len)
        ld c,a
        call mul8u
        ld c,100
        call div16_8
        ld b,l
__D_game_30_ph_aim_grow:  ld a,(aim_n)
        cp b
        ret nc
        push bc
        call aim_plot
        pop bc
        jr c,__D_game_30_ph_aim_clip
        ld hl,aim_n
        inc (hl)
        jr __D_game_30_ph_aim_grow
__D_game_30_ph_aim_clip:  ld a,(aim_n)
        ld (aim_len),a
        ret
__D_game_30_ph_aim_full:  cp 112
        ret c
        ; erase the line and strike
        call aim_reset
        ld a,(aim_n)
        or a
        jr z,__D_game_30_ph_aim_go
        ld b,a
__N_game_1_6:      push bc
        call aim_plot
        pop bc
        djnz __N_game_1_6
__D_game_30_ph_aim_go:    ld ix,BODIES+STRIKER*BSZ
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

; 45 bytes — Runs physics until the board settles, then hands the wreckage to the resolver.
ph_move:
        call phys_tick
        ld hl,(ticks)
        inc hl
        ld (ticks),hl
        ld a,(any_moving)
        or a
        jr z,__D_game_31_ph_move_done
        ld de,1500
        or a
        sbc hl,de
        ret c
        ld ix,BODIES
        ld b,NB
__N_game_1_7:      call body_stop
        ld de,BSZ
        add ix,de
        djnz __N_game_1_7
__D_game_31_ph_move_done:  ld a,PH_RESOLVE
        ld (phase),a
        ret

; ---------------------------------------------------------------- the rules (ICF Laws, doubles)
; 1972 bytes total — Applies the Carrom rules, including the queen's impressive paperwork.

; A = pocketed coin id 0..17.  Return C = coin colour and remember that this
; colour has reached a pocket this board.  HL/B survive the trip.
; 20 bytes — Records ordinary pocket history by colour so queen eligibility remembers reality.
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

; 587 bytes — Classifies the stroke, pockets, fouls, queen state, dues, and continuation rights.
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
        jr z,__D_game_33_ph_resolve_counted
        ld b,a
        ld hl,pk_ids
__D_game_33_ph_resolve_c:     ld a,(hl)
        inc hl
        cp STRIKER
        jr nz,__N_game_1_8
        ld a,1
        ld (rS),a
        jr __D_game_33_ph_resolve_cn
__N_game_1_8:      cp QUEEN
        jr nz,__N_game_2_3
        ld a,1
        ld (rQ),a
        jr __D_game_33_ph_resolve_cn
__N_game_2_3:      call record_coin_history
        ld a,(rcA)
        cp c
        jr nz,__N_game_3_1
        ld a,(rn)
        inc a
        ld (rn),a
        jr __D_game_33_ph_resolve_cn
__N_game_3_1:      ld a,(rm)
        inc a
        ld (rm),a
__D_game_33_ph_resolve_cn:    djnz __D_game_33_ph_resolve_c
__D_game_33_ph_resolve_counted:
        ; ICF 44, 45: the break is made once the striker touches a coin
        ld a,(break_made)
        or a
        jr nz,__D_game_33_ph_resolve_broken
        ld a,(touched)
        or a
        jr nz,__D_game_33_ph_resolve_mkbreak
        ld a,(rS)
        or a
        jr z,__D_game_33_ph_resolve_att
        xor a
        ld (attempts),a
        ld hl,S_BRKFOUL
        jp turn_pass
__D_game_33_ph_resolve_att:   ld hl,attempts
        inc (hl)
        ld a,(hl)
        cp 3
        jr c,__D_game_33_ph_resolve_again
        ld (hl),0
        ld hl,S_BRKLOST
        jp turn_pass
__D_game_33_ph_resolve_again: ld hl,S_BRKAGAIN
        jp turn_stay
__D_game_33_ph_resolve_mkbreak:
        ld a,1
        ld (break_made),a
        xor a
        ld (attempts),a
__D_game_33_ph_resolve_broken:
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
        jr nc,__N_game_4_0
        xor a
__N_game_4_0:      ld (hl),a
        ld a,e
        xor 1
        ld e,a
        ld hl,left
        add hl,de
        ld a,(rm)
        ld c,a
        ld a,(hl)
        sub c
        jr nc,__N_game_5_0
        xor a
__N_game_5_0:      ld (hl),a
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
        jr nz,__N_game_6_0
        inc a
__N_game_6_0:      ld (rqp),a
        ld a,(qstate)
        cp 2
        ld a,0
        jr nz,__N_game_7_0
        ld a,(qcover)
__N_game_7_0:      ld (rqc),a
        ; ---- the queen and the turn (ICF 48, 92-101)
        ld a,(rS)
        or a
        jr z,__D_game_33_ph_resolve_nos
        ld a,1
        ld (rnewdue),a           ; 72a: a pocketed striker costs a coin
        ld a,(rqp)
        or a
        jr z,__D_game_33_ph_resolve_s2
        ld a,(rn)
        or a
        jr z,__D_game_33_ph_resolve_s1r
        ld a,(qpend)
        cp 2
        jr nc,__D_game_33_ph_resolve_s1r
        ld a,2
        ld (qpend),a
        ld a,QA_PEND
        ld (qa),a
        ld a,1
        ld (rcont),a             ; 101a: one more stroke to cover
        jp __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_s1r:   ld a,QA_RET
        ld (qa),a
        call n_cont
        jp __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_s2:    ld a,(rQ)
        or a
        jr z,__D_game_33_ph_resolve_s3
        ld a,QA_RET
        ld (qa),a
        ; Queen + own coin(s) + striker: all returns are due, and play continues.
        call n_cont             ; Z returns set only for the no-own-coin case
        jp nz,__D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_s2_no_own:
        ; Queen + striker with no own coin keeps the separate restricted case.
        ld a,(rbefore)
        cp 9
        jp z,__D_game_33_ph_resolve_qdone
        ld a,(rdueout)
        or a
        jp nz,__D_game_33_ph_resolve_qdone
        ld a,(rright)
        or a
        jp z,__D_game_33_ph_resolve_qdone
        ld a,1
        ld (rcont),a
        jp __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_s3:    call n_cont
        jp __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_nos:   ld a,(rqp)
        or a
        jr z,__D_game_33_ph_resolve_nq
        ld a,(rn)
        or a
        jr z,__D_game_33_ph_resolve_nqr
        ld a,QA_COVER            ; 96: covered by a coin of his own
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_nqr:   ld a,QA_RET              ; 96: not covered, she goes back
        ld (qa),a
        jr __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_nq:    ld a,(rQ)
        or a
        jr z,__D_game_33_ph_resolve_nn
        ld a,(rdueout)
        or a
        jr nz,__D_game_33_ph_resolve_nqr               ; 95b
        ld a,(rn)
        or a
        jr nz,__D_game_33_ph_resolve_q3
        ld a,(rm)
        or a
        jr nz,__D_game_33_ph_resolve_nqr               ; 125
        ld a,(rright)
        or a
        jr z,__D_game_33_ph_resolve_nqr                ; 95a: no right to the queen yet
        ld a,QA_PEND             ; 92
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_q3:    ld a,(rbefore)
        cp 9
        jr nz,__D_game_33_ph_resolve_q4
        ld a,(rn)
        cp 1
        jr nz,__D_game_33_ph_resolve_q4
        ld a,QA_PEND             ; 97b: has to be covered
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_q4:    ld a,QA_COVER            ; 97a
        ld (qa),a
        ld a,1
        ld (rcont),a
        jr __D_game_33_ph_resolve_qdone
__D_game_33_ph_resolve_nn:    call n_cont              ; 48
__D_game_33_ph_resolve_qdone:
        ; Pocket-event colour history was recorded while pk_ids were counted.
        ; Returns later in this routine must not erase that board-long fact.
        ; ---- end of the board? (ICF 52, 53, 102-112)
        call board_result
        jp c,finish_board
        ; ---- the queen's fate
        ld a,(qa)
        cp QA_PEND
        jr nz,__N_game_9_0
        ld a,1
        ld (qstate),a
        ld a,(qpend)
        or a
        jr nz,__N_game_9_0
        inc a
        ld (qpend),a
__N_game_9_0:      ld a,(qa)
        cp QA_COVER
        jr nz,__N_game_10_0
        ld a,2
        ld (qstate),a
        ld a,(rcA)
        inc a
        ld (qcover),a
        xor a
        ld (qpend),a
__N_game_10_0:     ; ---- coins to put back: striker-forced own coins and Due for both colours
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
        jr nz,__D_game_33_ph_resolve_queen_done
        ld hl,FREESPOTS          ; ICF 93, 94: the queen goes back to the centre
        call find_spot
        jr nc,__D_game_33_ph_resolve_queen_spot
        ; Impossible placement: keep a nonzero Queen state and replay cleanly.
        ld a,1
        ld (qstate),a
        xor a                    ; PH_NEWBOARD
        ld (phase),a
        ret
__D_game_33_ph_resolve_queen_spot:
        ld ix,BODIES+QUEEN*BSZ
        call put_back
        xor a
        ld (qstate),a
        ld (qpend),a
__D_game_33_ph_resolve_queen_done:
        ld a,(rcA)
        xor 1                    ; settle the other colour's old Due first
        ld c,0
; 172 bytes — Finishes the opposite-colour due path and rejoins the common resolver tail.
due_other_call:
        call return_colour
        ld c,0
        ld a,(rS)
        or a
        jr z,__N_game_11_0
        ld a,(rn)
        ld c,a                   ; striker forces these mover-colour coins back
__N_game_11_0:     ld a,(rcA)
        call return_colour       ; mover last keeps rgiven friendly with the old score bookkeeping
        call stats_stroke
        call c,stats_clear
        ; ---- the message and the turn
        call msg_clear
        ld a,(rS)
        or a
        jr z,__D_game_34_due_other_call_m1
        ld hl,S_FOUL
        call msg_s
        jr __D_game_34_due_other_call_mturn
__D_game_34_due_other_call_m1:    ld a,(qa)
        cp QA_COVER
        jr nz,__D_game_34_due_other_call_m2
        ld hl,S_QCOVER
        call msg_s
        ld a,(rA)
        call msg_pair
        jr __D_game_34_due_other_call_mturn
__D_game_34_due_other_call_m2:    cp QA_PEND
        jr nz,__D_game_34_due_other_call_m3
        ld hl,S_QPEND
        call msg_s
        jr __D_game_34_due_other_call_mturn
__D_game_34_due_other_call_m3:    cp QA_RET
        jr nz,__D_game_34_due_other_call_m4
        ld hl,S_QRET
        call msg_s
        jr __D_game_34_due_other_call_mturn
__D_game_34_due_other_call_m4:    ld a,(rn)
        or a
        jr z,__D_game_34_due_other_call_m5
        ld hl,S_POCKETED
        call msg_s
        ld a,(rn)
        call msg_n
        jr __D_game_34_due_other_call_mturn
__D_game_34_due_other_call_m5:    ld a,(rm)
        or a
        jr z,__D_game_34_due_other_call_m6
        ld hl,S_OPPCOIN
        call msg_s
        jr __D_game_34_due_other_call_mturn
__D_game_34_due_other_call_m6:    ld hl,S_NOPOCKET
        call msg_s
__D_game_34_due_other_call_mturn: ld a,(rcont)
        or a
        jr z,__D_game_34_due_other_call_adv
        ld hl,S_CONT
        call msg_s
        call record_progress     ; a lawful continuation breaks the pass sequence
        jr __D_game_34_due_other_call_fin
__D_game_34_due_other_call_adv:   ld hl,S_PASS
        call msg_s
        call pass_turn
        ret c                    ; threshold schedules a clean replay of this board
__D_game_34_due_other_call_fin:   call msg_show
        call render
        call hud
        ld a,50
        ld c,PH_THINK0
        jp wait_then

; 11 bytes — Marks a continuation when at least one own coin earned another go.
n_cont: ld a,(rn)
        or a
        ret z
        ld a,1
        ld (rcont),a
        ret

; One actual turn pass. Carry means ICF 137 reached three passes by each of
; the four doubles players, so this same board is scheduled for a clean replay.
; 29 bytes — Advances the seat and detects the twelve-pass clean-board replay threshold.
pass_turn:
        ld hl,pass_streak
        inc (hl)
        ld a,(hl)
        cp PASS_REPLAY_LIMIT
        jr c,__D_game_36_pass_turn_advance
        xor a
        ld (hl),a
        ld a,PH_NEWBOARD
        ld (phase),a
        scf
        ret
__D_game_36_pass_turn_advance:
        ld a,(seat)
        inc a
        and 3
        ld (seat),a
        or a                    ; clear carry
        ret

; 5 bytes — Clears the pass streak after genuine progress, mercifully ending the count.
record_progress:
        xor a
        ld (pass_streak),a
        ret

; 14 bytes — Builds a pass message, advances the seat, and checks replay rules.
turn_pass:      ; HL = message, the turn goes to the next seat
        push hl
        call msg_clear
        pop hl
        call msg_s
        call pass_turn
        ret c
        jr turn_end
; 8 bytes — Builds a continuation message while leaving the current seat exactly where it is.
turn_stay:
        push hl
        call msg_clear
        pop hl
        call msg_s
; 21 bytes — Shows the turn result and schedules the next thinking phase.
turn_end:
        ld a,F_ON                ; hand the striker on visibly, even after a striker foul
        ld (BODIES+STRIKER*BSZ+BF),a
        call msg_show
        call render
        call hud
        ld a,50
        ld c,PH_THINK0
        jp wait_then


; A = coin colour, C = forced returns before Due. Returns that colour only.
; rret[colour] gets how many coins really came back, so the running score stays sane.
; 118 bytes — Returns forced and due coins of one colour without double-paying the debt.
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
__D_game_41_return_colour_loop:  push bc
        ld a,(rgiven)
        ld hl,rgive
        cp (hl)
        jr nc,__D_game_41_return_colour_next
        ld a,(rid)
        call body_ptr
        ld a,(ix+BF)
        and F_ON
        jr nz,__D_game_41_return_colour_next
        ld hl,DUESPOTS
        call find_spot
        jr nc,__N_game_2_4
        ld hl,FREESPOTS
        call find_spot
        jr c,__D_game_41_return_colour_next
__N_game_2_4:      call put_back
        ld hl,rgiven
        inc (hl)
__D_game_41_return_colour_next:  ld hl,rid
        inc (hl)
        pop bc
        djnz __D_game_41_return_colour_loop
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
        jr nc,__N_game_3_2
        xor a
__N_game_3_2:      ld b,a                   ; B = returns that actually pay Due
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
; 14 bytes — Converts a body id into IX pointing at its 24-byte body record.
body_ptr:
        ld b,a
        ld c,BSZ
        call mul8u
        ld de,BODIES
        add hl,de
        push hl
        pop ix
        ret

; 22 bytes — Finds a legal return spot and reactivates one coin on the board.
put_back:       ; IX = body, B = x, C = y (pixels)
        call body_stop
        ld (ix+BX+1),b
        ld (ix+BX),0
        ld (ix+BY+1),c
        ld (ix+BY),0
        ld (ix+BF),F_ON
        ret

; first spot from table HL where a coin touches nothing: B=x C=y, carry if none
; 25 bytes — Walks the preferred return positions until one is actually free.
find_spot:
__D_game_44_find_spot_lp:    ld a,(hl)
        cp 128
        jr z,__D_game_44_find_spot_none
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
        jr c,__D_game_44_find_spot_lp
        or a
        ret
__D_game_44_find_spot_none:  scf
        ret

; carry if a coin at (B,C) could overlap a coin on the board. Preserves BC.
; Integer body centres use the exact radius-eight test. Fractional 8.8 centres
; use a conservative high-byte bound: every accepted point is provably >=8 px.
; 95 bytes — Tests a proposed returned-coin centre against every active body in subpixels.
spot_free:
        push ix
        ld ix,BODIES
        ld e,NB
__D_game_45_spot_free_lp:    ld a,(ix+BF)
        and F_ON
        jr z,__D_game_45_spot_free_nx
        ld a,(ix+BX+1)
        sub b
        jr nc,__N_game_1_9
        neg
__N_game_1_9:      cp 10
        jr nc,__D_game_45_spot_free_nx
        ld h,a
        ld a,(ix+BY+1)
        sub c
        jr nc,__N_game_2_5
        neg
__N_game_2_5:      cp 10
        jr nc,__D_game_45_spot_free_nx
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
        ld a,(ix+BX)
        or (ix+BY)
        jr nz,__N_game_3_3
        ld a,l
        cp 64                   ; exact integer tangent is legal
        jr nc,__D_game_45_spot_free_nx
__N_game_3_3:      ld a,l
spot_threshold EQU $
        cp 86                   ; worst fractional drift keeps true d^2 >= 64
        jr nc,__D_game_45_spot_free_nx
        pop ix
        scf
        ret
__D_game_45_spot_free_nx:    push de
        ld de,BSZ
        add ix,de
        pop de
        dec e
        jr nz,__D_game_45_spot_free_lp
        pop ix
        or a
        ret

; ---- ICF 52, 53, 102-112: does this stroke end the board?  carry -> rW, rP
; 398 bytes — Decides the board winner, queen value, score, and whether another board is required.
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
        jr z,__N_game_1_10
        ld a,(r_a)
        or a
        jr nz,__N_game_1_10
        inc a
        ld (r_ownl),a
__N_game_1_10:      ld a,e
        xor 1
        ld e,a
        ld hl,left
        add hl,de
        ld a,(hl)
        ld (r_b),a
        ld a,(rm)
        or a
        jr z,__N_game_2_6
        ld a,(r_b)
        or a
        jr nz,__N_game_2_6
        inc a
        ld (r_oppl),a
__N_game_2_6:      ld a,(r_ownl)
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
        jr nz,__N_game_3_4
        inc a
__N_game_3_4:      ld c,a
        ld a,(qa)
        cp QA_COVER
        jr nz,__N_game_4_1
        ld c,1
__N_game_4_1:      ld a,c
        ld (r_qcA),a
        ld a,(rqc)
        or a
        jr z,__N_game_5_1
        cp b
        ld a,1
        jr nz,__N_game_6_1
__N_game_5_1:      xor a
__N_game_6_1:      ld (r_qcB),a
        ld a,(rQ)
        ld hl,rqp
        or (hl)
        ld hl,rqc
        or (hl)
        ld a,0
        jr nz,__N_game_7_1
        inc a
__N_game_7_1:      ld (r_qon),a
        ld a,(rA)
        ld (r_pa),a
        xor 1
        ld (r_pb),a
        ld a,(rS)
        or a
        jp z,__D_game_46_board_result_nostrk
        ; -- the striker went down with the last coin(s)
        ld a,(r_pb)
        ld (rW),a
        ld a,(r_ownl)
        ld hl,r_oppl
        and (hl)
        jr z,__D_game_46_board_result_s_one
        ld a,(rQ)
        or a
        jr nz,__D_game_46_board_result_s_a               ; 109a
        ld a,(r_qcA)
        or a
        jr z,__D_game_46_board_result_s_a
        ld a,2                   ; 110a
        jp __D_game_46_board_result_ret
__D_game_46_board_result_s_a:   call qv_b
        inc a
        jp __D_game_46_board_result_ret
__D_game_46_board_result_s_one: ld a,(r_ownl)
        or a
        jr z,__D_game_46_board_result_s_opp
        ld a,(r_qon)
        or a
        ret z                    ; the coin goes back instead (ICF 73/98/101)
        call qv_b                ; 108a
        inc a
        jp __D_game_46_board_result_ret
__D_game_46_board_result_s_opp: ld a,(r_qon)
        or a
        jr z,__D_game_46_board_result_s_o2
        call qc_b                ; 111a
        jr __D_game_46_board_result_s_o3
__D_game_46_board_result_s_o2:  ld a,(r_qcB)
        or a
        jr z,__D_game_46_board_result_s_o3
        call qc_b
__D_game_46_board_result_s_o3:  ld hl,r_a
        add a,(hl)
        inc a
        jp __D_game_46_board_result_ret
__D_game_46_board_result_nostrk:
        ld a,(r_ownl)
        ld hl,r_oppl
        and (hl)
        jr z,__D_game_46_board_result_n_one
        ; both colours finished by one stroke
        ld a,(rqp)
        ld hl,rQ
        or (hl)
        jr nz,__D_game_46_board_result_n_bA              ; 102a, 104a
        ld a,(r_qon)
        or a
        jr z,__D_game_46_board_result_n_b2
        ld a,(r_pb)              ; 105a
        ld (rW),a
        call qv_b
        jr __D_game_46_board_result_ret
__D_game_46_board_result_n_b2:  ld a,(r_qcA)
        or a
        jr nz,__D_game_46_board_result_n_bA
        ld a,(r_pa)
        ld (rW),a
        ld a,1
        jr __D_game_46_board_result_ret
__D_game_46_board_result_n_bA:  ld a,(r_pa)
        ld (rW),a
        call qv_a
        jr __D_game_46_board_result_ret
__D_game_46_board_result_n_one: ld a,(r_ownl)
        or a
        jr z,__D_game_46_board_result_n_opp
        ; the mover pocketed his last coin
        ld a,(r_pa)
        ld (rW),a
        ld a,(rQ)
        ld hl,rqp
        or (hl)
        ld hl,r_qcA
        or (hl)
        jr z,__D_game_46_board_result_n_o1
        call qc_a                ; 97, 52, 53b
        ld hl,r_b
        add a,(hl)
        jr __D_game_46_board_result_ret
__D_game_46_board_result_n_o1:  ld a,(r_qcB)
        or a
        jr z,__D_game_46_board_result_n_o2
        ld a,(r_b)               ; 53c
        jr __D_game_46_board_result_ret
__D_game_46_board_result_n_o2:  ld a,(r_pb)              ; 107a: last coin while the queen is on the board
        ld (rW),a
        call qv_b
        jr __D_game_46_board_result_ret
__D_game_46_board_result_n_opp: ; the mover pocketed the opponent's last coin
        ld a,(r_pb)
        ld (rW),a
        ld a,(rqp)
        ld hl,r_qon
        or (hl)
        ld hl,rQ
        or (hl)
        jr z,__D_game_46_board_result_n_p1
        call qc_b                ; 103a, 106a
        jr __D_game_46_board_result_n_p3
__D_game_46_board_result_n_p1:  ld a,(r_qcB)
        or a
        jr z,__D_game_46_board_result_n_p3
        call qc_b
__D_game_46_board_result_n_p3:  ld hl,r_a
        add a,(hl)
__D_game_46_board_result_ret:   ld (rP),a
        scf
        ret

; queen value for pair A/B: 3 points, or 1 from a score of 22 (ICF 102-112)
; 5 bytes — Fetches pair A's queen-value contribution.
qv_a:   ld a,(r_pa)
        jr qv
; 3 bytes — Selects pair B before sharing the queen-value calculation.
qv_b:   ld a,(r_pb)
; 11 bytes — Returns the queen value applicable to the selected pair.
qv:     call pscore
        cp 22
        ld a,3
        ret c
        ld a,1
        ret
; queen credit: 3, or 0 from a score of 22 (ICF 52b, 54)
; 5 bytes — Fetches pair A's queen-coverage state.
qc_a:   ld a,(r_pa)
        jr qc
; 3 bytes — Selects pair B before sharing the queen-coverage lookup.
qc_b:   ld a,(r_pb)
; 10 bytes — Returns whether the selected pair owns the covered queen.
qc:     call pscore
        cp 22
        ld a,3
        ret c
        xor a
        ret
; 9 bytes — Reads one pair's current board score from the compact score fields.
pscore: ld e,a
        ld d,0
        ld hl,game_score
        add hl,de
        ld a,(hl)
        ret

; 130 bytes — Banks the board result, updates counters, and chooses the next result phase.
finish_board:
        call stats_board
        push af
        ld a,(rP)
        cp 13
        jr c,__N_game_1_11
        ld a,12                  ; ICF 55: at most 12 points a board
__N_game_1_11:      ld (rP),a
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
        jr nc,__D_game_54_finish_board_stats_reset
        pop af
        call c,stats_clear
        jr __D_game_54_finish_board_stats_done
__D_game_54_finish_board_stats_reset:
        pop af
        call stats_clear
__D_game_54_finish_board_stats_done:
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
; 161 bytes — Plays the board result, handles ties, and schedules the next breaker.
ph_afterboard:
        ld a,(game_score)
        cp 25
        jr nc,__D_game_55_ph_afterboard_g
        ld a,(game_score+1)
        cp 25
        jr nc,__D_game_55_ph_afterboard_g
        ld a,(boards_in_game)
        cp 8
        jr c,__D_game_55_ph_afterboard_nog
        ld a,(game_score)
        ld hl,game_score+1
        cp (hl)
        jr nz,__D_game_55_ph_afterboard_g
        ; ICF extra board after a tied eighth board: choose a fresh logical breaker.
        ld c,4
        call rand_n
        ld (extra_breaker),a
        ld a,1
        ld (extra_board),a
__D_game_55_ph_afterboard_nog:   ld a,PH_NEWBOARD
        ld (phase),a
        ret
__D_game_55_ph_afterboard_g:     ld a,(game_score)
        ld hl,game_score+1
        cp (hl)
        ld a,0
        jr nc,__N_game_1_12
        inc a
__N_game_1_12:      ld (rA),a
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
        jr nz,__N_game_2_7
        ld hl,gw
        inc (hl)
__N_game_2_7:      call msg_clear
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

; 96 bytes — Plays the game result, rotates players, and either continues or ends the match.
ph_aftergame:
        ld a,(gw)
        cp 2
        jr nc,__D_game_56_ph_aftergame_m
        ld b,a
        ld a,(games_played)
        sub b
        cp 2
        jr nc,__D_game_56_ph_aftergame_m
        call rotate_players_right
        call new_game
        jp hud
__D_game_56_ph_aftergame_m:     call msg_clear
        ld hl,S_MATCH
        call msg_s
        ld a,(gw)
        cp 2
        ld a,0
        jr nc,__N_game_1_13
        inc a
__N_game_1_13:      call msg_pair
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

; A = colour, B = pocketed this stroke. rret[colour] says how many really came back.
; 67 bytes — Updates this colour's pocket-minus-return change in the pair's running total.
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
        jr c,__D_game_57_stats_colour_add
        sub b
        ld c,a
        ld a,(hl)
        sub c
        jr nc,__D_game_57_stats_colour_store
        add a,100
        ld (hl),a
        inc hl
        inc hl
        ld a,(hl)
        or a
        jr z,__D_game_57_stats_colour_zero
        dec (hl)
        ret
__D_game_57_stats_colour_zero:  xor a
        dec hl
        dec hl
        ld (hl),a
        ret
__D_game_57_stats_colour_add:   ld a,b
        sub c
        ld c,a
        ld a,(hl)
        add a,c
        cp 100
        jr c,__D_game_57_stats_colour_store
        sub 100
        ld (hl),a
        inc hl
        inc hl
        inc (hl)
        ld a,(hl)
        cp 10
        ccf
        ret
__D_game_57_stats_colour_store: ld (hl),a
        or a
        ret

; 14 bytes — Clears public counters when their display bounds finally say enough.
stats_clear:
        xor a
        ld hl,score
        ld (hl),a
        ld de,score+1
        ld bc,7
        ldir
        ret

; ---------------------------------------------------------------- HUD
; 423 bytes total — Keeps scores and status readable while the coins cause trouble.
; Each corner is 6 character cells = 12 columns of the 64-column font:
;   row 1   RED (o)x9 DUE       name, coin colour, coins left, dues owed
;   row 2   PTS 125 (Q)         running points (3 digits), queen covered
;   row 21  GAMES  2            games won (2 digits)
;   row 22  BOARDS12            boards won (2 digits)
; The two row-1 side-marker cells stay boring on purpose in the board attributes.

; 6 bytes — Draws the two pair score panels; delegation keeps its hands clean.
hud:
        xor a
        call hud_pair
        ld a,1
; 282 bytes — Draws one complete pair panel with colour marker, due, points, boards, and games.
hud_pair:
        ld (hp_p),a
        ld c,0
        or a
        jr z,__N_game_1_14
        ld c,52
__N_game_1_14:      ld a,c
        ld (hp_col),a
        ld a,(hp_p)
        call pair_colour
        ld (hp_c),a
        ; row 1: name, coin colour, coins left, dues
        ld a,(hp_p)
        ld hl,S_RED
        or a
        jr z,__N_game_2_8
        ld hl,S_BLU
__N_game_2_8:      ld de,0x0100
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
        jr nz,__N_game_3_5
        ld hl,S_NODUE
__N_game_3_5:      ld de,0x0108
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
        jr z,__N_game_6_2
        add a,'0'
        jr __N_game_7_2
__N_game_6_2:      ld a,' '
__N_game_7_2:      ld de,0x0204
        call hud_ch
        pop af
        ld de,0x0205
        call hud_num2
        ld a,' '
        ld de,0x0207
        call hud_ch
        ld a,(qstate)            ; queen covered by this side
        cp 2
        jr nz,__N_game_4_2
        ld a,(qcover)
        dec a
        ld hl,hp_c
        cp (hl)
        jr nz,__N_game_4_2
        ld a,130
        ld de,0x0208
        call hud_ch
        jr __N_game_5_2
__N_game_4_2:      ld hl,S_NODUE+2          ; two spaces
        ld de,0x0208
        call hud_s
__N_game_5_2:      ld hl,S_NODUE+2
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
; 11 bytes — Prints one ordinary HUD character at the current half-width cursor.
hud_ch:
        ld b,d
        push af
        ld a,(hp_col)
        add a,e
        ld c,a
        pop af
        jp put64
; string HL at row D, column hp_col+E
; 9 bytes — Prints one zero-terminated HUD string and advances its cursor.
hud_s:
        ld b,d
        ld a,(hp_col)
        add a,e
        ld c,a
        jp print64
; A (0-99) right-aligned in two columns at D,E
; 8 bytes — Formats a two-digit HUD value with the requested leading behaviour.
hud_num2:
        call num_digits
        ld a,(nd_d+1)
        jr hud_dig2
; 7 bytes — Prints the tens digit before falling through to the units digit.
hud_dig2:
        call hud_dig
        inc e
        ld a,(nd_d+2)
; 6 bytes — Prints one decimal HUD digit and advances the cursor.
hud_dig:
        push de
        call hud_ch
        pop de
        ret
; A -> nd_d: three digit characters, leading zeros as spaces (units always a digit)
; 44 bytes — Chooses decimal width for bounded public counters without wasting a formatter.
num_digits:
        ld b,'0'-1
__N_game_1_15:      inc b
        sub 100
        jr nc,__N_game_1_15
        add a,100
        ld c,'0'-1
__N_game_2_9:      inc c
        sub 10
        jr nc,__N_game_2_9
        add a,10+'0'
        ld (nd_d+2),a
        ld a,b
        cp '0'
        jr nz,__N_game_3_6
        ld b,' '
        ld a,c
        cp '0'
        jr nz,__N_game_3_6
        ld c,' '
__N_game_3_6:      ld a,b
        ld (nd_d),a
        ld a,c
        ld (nd_d+1),a
        ret

; 18 bytes — Appends the current robot personality name to the status message.
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
; 2466 bytes total — Chooses robot shots, scores options, and converts intent into velocity.
;
; Candidate generation (ghost-coin aiming at each pocket for every legal target), a cheap
; geometric check of both paths, then utility scoring with a per-player weighting profile:
;   player 0 AGGRESSIVE, 1 BALANCED, 2 DEFENSIVE, 3 TRICKSTER
; Coordinates are in the seat frame, in half pixels: u along the baseline, v forward.

; profile: wc, wd, cmin, qbonus(2), cutbonus, margin(/64), jitter(1/16 px)
; Wider legal cuts and stronger useful-shot weighting make every profile more
; decisive without changing the established bounded-random call set.
PROFILES:
        db 10,2,14
        dw 300
        db 0,88,5
        db 10,2,16
        dw 180
        db 0,84,4
        db 12,1,20
        dw 120
        db 0,80,3
        db 7,2,12
        dw 200
        db 2,86,6
PF_WC   EQU 0
PF_WD   EQU 1
PF_CMIN EQU 2
PF_QB   EQU 3
PF_CUT  EQU 5
PF_MARG EQU 6
PF_JIT  EQU 7

; 192 bytes — Initialises the robot planner, candidate lists, profile weights, and best-score abyss.
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
        ; Planner invites body ids 0..18 only; striker id 19 waits outside.
        ; Every planner helper uses the same guest list, because debugging is expensive.
        ld ix,BODIES
        ld b,0
__D_game_69_ai_begin_lp:    push bc
        ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(ix+BF)
        and F_ON
        ld (hl),a
        jr z,__D_game_69_ai_begin_nx
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
__D_game_69_ai_begin_nx:    ld de,BSZ
        add ix,de
        pop bc
        inc b
        ld a,b
        cp 19
        jr c,__D_game_69_ai_begin_lp
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
        jr nz,__N_game_1_16
        ld a,1
        ld (ai_mode),a           ; the break
        ret
__N_game_1_16:      call mover_colour
        ld (ai_col),a
        ld b,a
        add a,a
        add a,a
        add a,a
        add a,b
        ld c,a                   ; first id of my colour
        ld b,9
__D_game_69_ai_begin_t:     push bc
        ld e,c
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        call nz,ai_addt
        pop bc
        inc c
        djnz __D_game_69_ai_begin_t
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
; 16 bytes — Adds one target body to the planner's compact target list if room remains.
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
; 27 bytes — Evaluates one planner candidate per frame so thinking never freezes the match.
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

; 343 bytes — Scores one target-pocket-placement combination for legality and usefulness.
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
        jr z,__N_game_1_17
        ld c,34
__N_game_1_17:      ld b,-34
        bit 1,a
        jr z,__N_game_2_10
        ld b,34
__N_game_2_10:      ld a,c
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
        jp p,__D_game_72_ai_eval_back
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
__D_game_72_ai_eval_back:  ; the pocket is behind the coin: cut it back from the far side
        ld a,(ev_dx)
        or a
        ld b,24
        jp m,__N_game_3_7
        ld b,-24
__N_game_3_7:      ld a,(ev_cu)
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
        jp m,__N_game_4_3
        ld b,-12
__N_game_4_3:      ld a,(ev_cu)
        add a,b
        ld l,a
        rla
        sbc a,a
        ld h,a
        call clamp28
        jp ai_place

; HL signed -> A clamped to -28..28
; 25 bytes — Clamps a signed baseline coordinate to the legal half-pixel planning range.
clamp28:
        ld de,28
        bit 7,h
        jr nz,__N_game_1_18
        push hl
        or a
        sbc hl,de
        pop hl
        ld a,l
        ret c
        ld a,28
        ret
__N_game_1_18:      push hl
        add hl,de
        pop hl
        ld a,l
        ret c
        ld a,-28
        ret

; 4 bytes — Arithmetic-shifts HL right seven places for compact fixed-point scaling.
sra7:   ld b,7
        jr __N_game_1_19
; 9 bytes — Arithmetic-shifts HL right six places, one bit more patiently.
sra6:   ld b,6
__N_game_1_19:      sra h
        rr l
        djnz __N_game_1_19
        ret

; A = round-down sqrt(B*B + C*C), signed B, C
; 32 bytes — Approximates an 8-bit vector length cheaply enough for repeated planning.
len8:
        ld a,b
        or a
        jp p,__N_game_1_20
        neg
__N_game_1_20:      ld b,a
        ld a,c
        or a
        jp p,__N_game_2_11
        neg
__N_game_2_11:      push af
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
; 35 bytes — Divides signed HL by 64 with planner-friendly rounding.
div64:
        ld (sd_sign),a
        or a
        jp p,__N_game_1_21
        neg
__N_game_1_21:      ld l,a
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
; 291 bytes — Searches legal striker placements and keeps the best-scoring route.
ai_place:
        cp 29
        jr c,__N_game_1_22
        cp -28 AND 255
        ret c
__N_game_1_22:      ld (ev_su),a
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
        jr nc,__N_game_2_12
        add a,a
        add a,a
        ld c,a                   ; 4*gv: at least 14 degrees off the baseline
        ld a,(ev_ux)
        or a
        jp p,__N_game_1_23
        neg
__N_game_1_23:      cp c
        ret nc
__N_game_2_12:
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
        jr nz,__N_game_5_3
        call ai_qscore
__N_game_5_3:      ld a,(pf+PF_CUT)
        or a
        jr z,__N_game_6_3
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
__N_game_6_3:      push hl
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
__N_game_8_0:      ret

; carry if a coin lies on the path A->B within sg_d pixels (half-pixel coordinates)
; 336 bytes — Checks a line segment against all relevant bodies and rejects obstructed paths.
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
__D_game_79_seg_blocked_lp:    push bc
        ld a,(sg_skip)
        cp b
        jp z,__D_game_79_seg_blocked_nx
        ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        jp z,__D_game_79_seg_blocked_nx
        ld hl,ai_u
        add hl,de
        ld a,(hl)
        ld (sg_ou),a
        xor 0x80
        ld hl,sg_umin
        cp (hl)
        jp c,__D_game_79_seg_blocked_nx
        inc hl
        cp (hl)
        jr z,__N_game_1_24
        jp nc,__D_game_79_seg_blocked_nx
__N_game_1_24:      ld hl,ai_v
        add hl,de
        ld a,(hl)
        ld (sg_ov),a
        xor 0x80
        ld hl,sg_vmin
        cp (hl)
        jp c,__D_game_79_seg_blocked_nx
        inc hl
        cp (hl)
        jr z,__N_game_2_13
        jp nc,__D_game_79_seg_blocked_nx
__N_game_2_13:      ; o = O - A
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
        jr nz,__D_game_79_seg_blocked_nx                ; behind the start
        ld de,(sg_l2)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,__D_game_79_seg_blocked_mid
        jr z,__D_game_79_seg_blocked_mid
        ld a,(sg_noend)
        or a
        jr nz,__D_game_79_seg_blocked_nx
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
        jr c,__D_game_79_seg_blocked_blk
        jr __D_game_79_seg_blocked_nx
__D_game_79_seg_blocked_mid:   ; perpendicular distance: |cross| / L < d/2  <=>  2|cross| < d*L
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
        jr c,__D_game_79_seg_blocked_blk
__D_game_79_seg_blocked_nx:    pop bc
        inc b
        ld a,b
        cp 19
        jp c,__D_game_79_seg_blocked_lp
        or a
        ret
__D_game_79_seg_blocked_blk:   pop bc
        scf
        ret

; B, A signed -> C = min-5, B = max+5 (both biased by 0x80): stored as (min,max)
; 32 bytes — Orders two signed endpoints so segment clipping has fewer opinions to manage.
minmax:
        xor 0x80
        ld c,a
        ld a,b
        xor 0x80
        ld b,a
        cp c
        jr c,__N_game_1_25
        ld a,c                   ; c <= b
        ld c,b
        ld b,a
__N_game_1_25:      ; now b = min, c = max
        ld a,b
        sub 5
        jr nc,__N_game_2_14
        xor a
__N_game_2_14:      ld b,a
        ld a,c
        add a,5
        jr nc,__N_game_3_8
        ld a,255
__N_game_3_8:      ld c,a
        ld a,b
        ld b,c
        ld c,a
        ret

; ---- turning the chosen candidate into a stroke

; 298 bytes — Commits the best plan or falls back deterministically when brilliance fails.
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
        jr z,__N_game_1_26
        ld hl,68
__N_game_1_26:      ld de,-68
        bit 1,a
        jr z,__N_game_2_15
        ld de,68
__N_game_2_15:      call from_seat16
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
        jr c,__N_game_3_9
        ex de,hl
__N_game_3_9:      ld (fc_vc),hl
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
        jr z,__N_game_4_4
        ld hl,VMAX
__N_game_4_4:      ld de,VMAX
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,__N_game_5_4
        ex de,hl
__N_game_5_4:      jp set_velocity

; DE:HL helpers ---------------------------------------------------
; body IX centre in 1/16 px: HL = x, DE = y
; 48 bytes — Loads one body centre into 16-bit board coordinates for planner geometry.
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
; 45 bytes — Approximates a 16-bit vector length without inviting a square-root library.
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
; 30 bytes — Computes the striker ghost offset behind a target coin at contact.
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
; 55 bytes — Adds bounded personality noise without nudging the shot outside legal arithmetic.
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
; 37 bytes — Converts planned baseline placement into striker centre coordinates.
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
; 45 bytes — Builds a normalised direction vector from striker to ghost contact point.
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
        jr nz,__N_game_1_27
        inc hl
__N_game_1_27:      ld (fc_lsg),hl
        ret

; HL = speed: velocity along fc_u, aim-line step, plan
; 41 bytes — Turns planned direction and speed into striker velocity components.
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
; 31 bytes — Computes one signed velocity component from normal and planned speed.
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
; 30 bytes — Computes one signed unit component used by the planner's geometry.
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
; 38 bytes — Creates a legal opening break plan before clever shot selection begins.
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
; 179 bytes — Tries the same safe fallback shots when every clever pocket plan has face-planted.
plan_fallback:
        xor a
        ld (fb_tier),a
__D_game_92_plan_fallback_tier:  ld hl,30000
        ld (fb_best),hl
        ld a,0xFF
        ld (fb_id),a
        ld b,0
__D_game_92_plan_fallback_lp:    push bc
        ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        jr z,__D_game_92_plan_fallback_nx
        ld a,b
        cp QUEEN
        jr z,__D_game_92_plan_fallback_nx
        ld a,b
        cp 9
        ccf
        ld a,0
        adc a,0
        ld hl,ai_col
        cp (hl)
        ld c,0
        jr z,__N_game_1_28
        ld c,40                  ; prefer my own colour
__N_game_1_28:      ld a,c
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
__D_game_92_plan_fallback_nx:    pop bc
        inc b
        ld a,b
        cp 19
        jr c,__D_game_92_plan_fallback_lp
        ld a,(fb_id)
        cp 0xFF
        jr nz,__D_game_92_plan_fallback_hit
        ld a,(fb_tier)          ; nothing with a clear path: just hit the nearest coin
        or a
        jr nz,__D_game_92_plan_fallback_mid
        inc a
        ld (fb_tier),a
        jp __D_game_92_plan_fallback_tier
__D_game_92_plan_fallback_mid:   call fallback_legal
        ret c                    ; every legal baseline point was blocked
        call place_xy
        ld hl,128*16
        ld (fc_gx),hl
        ld hl,96*16
        ld (fc_gy),hl
        jr __D_game_92_plan_fallback_go
__D_game_92_plan_fallback_hit:   ld a,(fb_su)
        add a,a
        ld (plan_u),a
        call place_xy
        ld a,(fb_id)
        call body_ptr
        call body16
        ld (fc_gx),hl
        ld (fc_gy),de
__D_game_92_plan_fallback_go:    call dir_to_target
        ld hl,6800
        jp set_velocity

; 148 bytes — Scores one fallback placement and target while keeping legality non-negotiable.
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
        jr nc,__N_game_2_16
        add a,a
        add a,a
        ld c,a
        ld a,(ev_ux)
        or a
        jp p,__N_game_1_29
        neg
__N_game_1_29:      cp c
        ret nc
__N_game_2_16:      ld a,(ev_su)
        call strike_legal
        ret c
        ld a,(fb_tier)
        or a
        jr nz,__N_game_3_10
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
__N_game_3_10:      ld a,(ev_ux)
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

; 7 bytes — Clamps signed A to the legal planning interval of minus to plus twenty-eight.
clamp_a28:
        ld l,a
        rla
        sbc a,a
        ld h,a
        jp clamp28

; carry if the striker at u = A (half px) on the baseline would touch a coin
; 81 bytes — Rejects striker placements that overlap any active ordinary coin or queen.
strike_legal:
        ld (lg_su),a
        ld b,0
__D_game_95_strike_legal_lg:    ld e,b
        ld d,0
        ld hl,ai_on
        add hl,de
        ld a,(hl)
        or a
        jr z,__D_game_95_strike_legal_n
        ld hl,ai_v
        add hl,de
        ld a,(hl)
        sub VB_HALF
        add a,5
        cp 10
        jr nc,__D_game_95_strike_legal_n
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
        jr nc,__D_game_95_strike_legal_n
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
__D_game_95_strike_legal_n:     inc b
        ld a,b
        cp 19
        jr c,__D_game_95_strike_legal_lg
        or a
        ret

; HL = A*A (A signed)
; 11 bytes — Squares signed A through the shared square table and returns the 16-bit result.
sq8:    or a
        jp p,__N_game_1_30
        neg
__N_game_1_30:      ld b,a
        ld c,a
        jp mul8u
