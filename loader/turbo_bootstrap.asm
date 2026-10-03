; Resident BASIC bootstrap. Copy the fast decoder to uncontended RAM,
; copy a tiny post-game reset stub below the game load address, then jump high.

        ORG 23784

DECODER_DEST  EQU 0xFB00
DECODER_BYTES EQU 512
RETURN_STUB   EQU 0x7F00

; 29 bytes — Copies the decoder and return stub into place, then gets out of the way.
bootstrap_start:
        di
        ld sp,0x7FF0

        ld hl,bootstrap_end
        ld de,DECODER_DEST
        ld bc,DECODER_BYTES
        ldir

        ld hl,reset_stub
        ld de,RETURN_STUB
        ld bc,reset_stub_end-reset_stub
        ldir

        jp DECODER_DEST

; 3 bytes — Tiny return trampoline; three bytes, one job, no drama.
reset_stub:
        jp 0
reset_stub_end:

bootstrap_end:
