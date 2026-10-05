; Built from ZQLoader by Daan Scherft/Oxidaan.
; MIT licence paperwork lives in ZQLOADER_LICENSE.txt.

; Tiny BASIC stowaway: copy the fast decoder to uncontended RAM,
; park a post-game reset stub below the game, then get out of the way.

        ORG 23784

DECODER_DEST  EQU 0xFB00
DECODER_BYTES EQU 512
RETURN_STUB   EQU 0x7F00

; 33 bytes — Copies the decoder and return stub into place, then politely vanishes.
bootstrap_start:
        di
        ld (reset_sp),sp        ; tuck BASIC's stack away before borrowing our own
        ld sp,0x7E00

        ld hl,bootstrap_end
        ld de,DECODER_DEST
        ld bc,DECODER_BYTES
        ldir

        ld hl,reset_stub
        ld de,RETURN_STUB
        ld bc,reset_stub_end-reset_stub
        ldir

        jp DECODER_DEST

; 4 bytes — Restores BASIC's stack without reaching for the big red reset lever.
reset_stub:
        ld sp,0x0000
reset_sp EQU reset_stub+1
        ret
reset_stub_end:

bootstrap_end:
