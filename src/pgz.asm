; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

pgz         .namespace

            .section    dp
state       .byte       ?
offset      .byte       ?
addr        .dword      ?
size        .dword      ?
psize       .word       ?
block       .byte       ?
ptr         .word       ?
            .send
            
STATE       .struct
SIGNATURE   .word       state_signature
BLOCK       .word       state_block
ADDR        .word       state_addr
SIZE        .word       state_size
BYTES       .word       state_bytes
EXEC        .word       state_exec
            .ends
            
            .section    code            

init
            stz     state
            clc
            rts
            
accept
    ; IN:   A = byte to process.
    
            phx
            phy

            ldx     #2
            stx     io_ctrl
            inc     $c001
            
            ldx     state
            jsr     _call
            stx     state
            txa
            lsr     a
            ora     #$40
            sta     $c002
            ply
            plx
            rts
_call
            clc
            jmp     (_vectors,x)
_vectors
            .dstruct STATE
            
state_signature
            cmp     #'Z'
            beq     _short
            cmp     #'z'
            beq     _long
            sec
            rts

_short
            lda     #3
            bra     _next
_long
            lda     #4
_next
            dec     a
            sta     psize
            ldx     #STATE.BLOCK
            clc
            rts


state_block
            pha

            ldx     #addr
            jsr     _zero
            ldx     #size
            jsr     _zero

            stz     offset
            ldx     #STATE.ADDR

            pla
            bra     state_addr
            
_zero
            stz     0,x
            stz     1,x
            stz     2,x
            stz     3,x
            rts

state_addr
            ldy     offset
            sta     addr,y
            inc     offset
            cpy     psize
            bcc     _out
            jsr     print_addr
            stz     offset
            ldx     #STATE.SIZE
            clc
_out
            rts            
            
state_size
            ldy     offset
            sta     size,y
            inc     offset
            cpy     psize
            bcc     _out

            jsr     print_size
            stz     offset
            ldx     #STATE.BYTES
            jsr     test_size
            bne     _out
            ldx     #STATE.EXEC
_out
            rts            
            
test_size
            lda     size+0
            ora     size+1
            ora     size+2
            ora     size+3
            clc
            rts

state_bytes

            jsr     store
            
            sec
            lda     size+0
            sbc     #1
            sta     size+0
            bcs     _out

            lda     size+1
            sbc     #0
            sta     size+1
            bcs     _out

            lda     size+2
            sbc     #0
            sta     size+2
            bcs     _out

            lda     size+3
            sbc     #0
            sta     size+3
_out
            jsr     test_size
            bne     _done
            
            ldx     #STATE.BLOCK
_done
            jsr     print_remaining
            clc
            rts

store2
            sta (addr)
          ; Increment the offset
            inc     addr+0
            bne     _out
            inc     addr+1
            bne     _out
            inc     addr+2
_out           
            jsr     print_addr 
            clc
            rts
            
store
            pha

          ; Compute the block.
            lda     addr+2
            sta     block
            lda     addr+1
            asl     a
            rol     block
            asl     a
            rol     block
            asl     a
            rol     block
            
          ; Map the block
            lda     #$80|$33
            sta     mmu_ctrl
            lda     block
            sta     mmu+1
            
          ; Compute the offset
            lda     addr+0
            sta     ptr+0
            lda     addr+1
            and     #$1f
            ora     #$20
            sta     ptr+1
            
          ; Store the byte
            pla
            sta     (ptr)

          ; Increment the offset
            inc     addr+0
            bne     _out
            inc     addr+1
            bne     _out
            inc     addr+2
_out           
            jsr     print_addr 
            clc
            rts

print_addr
            phx
            ldx     #4
            lda     addr+3
            jsr     print_hex
            lda     addr+2
            jsr     print_hex
            lda     addr+1
            jsr     print_hex
            lda     addr+0
            jsr     print_hex
            plx
            rts

print_size
            phx
            ldx     #16
            lda     size+3
            jsr     print_hex
            lda     size+2
            jsr     print_hex
            lda     size+1
            jsr     print_hex
            lda     size+0
            jsr     print_hex
            plx
            rts

print_remaining
            phx
            ldx     #26
            lda     size+3
            jsr     print_hex
            lda     size+2
            jsr     print_hex
            lda     size+1
            jsr     print_hex
            lda     size+0
            jsr     print_hex
            plx
            rts

print_hex
            pha
            lsr     a
            lsr     a
            lsr     a
            lsr     a
            jsr     _nibble
            pla
_nibble
            phy
            and     #$0f
            tay
            lda     _digits,y
            sta     $c000,x
            inx
            ply
            rts
_digits     .text   "0123456789abcdef"                        

            
state_exec
            sec
            rts
            
exec
            lda     state
            cmp     #STATE.EXEC
            beq     _exec
            sec
            rts
_exec
            
            ldx     #0
_loop
            lda     _code,x
            sta     $100,x
            inx
            cpx     #_end-_code
            bne     _loop
            jmp     $100
_code
            lda     #1
            sta     mmu+1
            jmp     (addr)
_end                   

            .send
            .endn
            
