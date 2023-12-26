; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

            .section    code

print_cr
            lda     #13
            bra     putchar
            
print_space
            lda     #32
            bra     putchar
            
print_byte
            pha
            jsr     print_hex
            jsr     print_space
            pla
            rts

print_word
            php
            pha
            lda     1,x
            jsr     print_hex
            lda     0,x
            jsr     print_hex
            jsr     print_space
            pla
            plp
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
            and     #$0f
            phy
            tay
            lda     _digits,y
            ply
            jmp     putchar
_digits     .text   "0123456789abcdef"            

putchar     jmp     display.putchar

            .send
            
display     .namespace


            .section    dp
cursor      .byte       ?   ; Cursor X offset.
src         .word       ?   ; Source pointer for copies.
dest        .word       ?   ; Dest pointer for copies.
line        .word       ?   ; Pointer to current text line.
            .send        

            .section    code

screen_init

            stz     cursor
            
            lda     #<($c000+80*3)
            sta     line+0
            lda     #>($c000+80*3)
            sta     line+1
            rts
            
            stz     io_ctrl

          ; Compute the address of the cursor's line.
          ; x80 = 64+16 = 16*(4+1)
            lda     #$0c    ; $c0 / 16
            sta     line+1
            lda     $d016   ; cursor y
            asl     a       ; x2
            asl     a       ; x4
            adc     $d016   ; +1
            sta     line+0
            bcc     +
            inc     line+1
+           asl     a       ; x16
            rol     line+1
            asl     a
            rol     line+1
            asl     a
            rol     line+1
            asl     a
            rol     line+1

            rts
            
 ;rts
            phx
            phy

          ; Fill the attributes.
            lda     #3
            sta     io_ctrl
            lda     #$10
            jsr     _fill
            
          ; Fill the characters.
            lda     #2
            sta     io_ctrl
            lda     #32
            jsr     _fill
            
            ply
            plx
            rts
        
_fill
            ldx     #<$c000
            stx     dest+0
            ldx     #>$c000
            stx     dest+1
    
          ; Round X up to the next whole number of pages.
          ; Slight overkill, but keeps the code simple.
            ldx     #>(80*61)+256
            ldy     #0
_loop  
            sta     (dest),y
            iny
            bne     _loop
            inc     dest+1
            dex
            bne     _loop
            
            clc
            rts

cursor_on: rts
          ; Switch the text under the cursor
          ; to white on yellow.
            lda     #$01
            bra     set_cursor
        
cursor_off: rts
          ; Switch the text under the cursor
          ; to white on yellow.
            lda     #$10
            bra     set_cursor
        
set_cursor
        ; A = the text color attributes.
    
            phy
    
          ; Stash a copy of the current I/O setting.
            ldy     io_ctrl
            phy
    
          ; Switch to text color memory.
            ldy     #3
            sty     io_ctrl
    
          ; Set the attribute
            ldy     cursor
            sta     (line),y
    
          ; Restore previous I/O setting.
            ply
            sty     io_ctrl
    
            ply
            clc
            rts
    
putchar
            pha
            jsr     cursor_off
            pla
    
            phx
            phy
            jsr     _putch
            ply
            plx
    
            jmp     cursor_on
    
_putch
            cmp     #32
            bcs     _ascii
            
            cmp     #8
            beq     _backspace
            
            cmp     #13
            beq     _cr
            
            cmp     #10
            beq     _lf
        
_done
            rts

_ascii
            ldy     cursor
            sta     (line),y
            iny
            sty     cursor
            cpy     #80
            bne     _done

_cr
_lf
            stz     cursor
            jmp     scroll

_backspace
            ldy     cursor
            beq     _done
            dey
            sty     cursor
            bra     _done

        
scroll
        ; I would normally keep a ring buffer and re-draw the
        ; screen, but this isn't really a terminal program, and
        ; games won't generally operate that way.
            lda     #2
            sta     io_ctrl
            
            lda     #<$c000+80
            sta     src+0
            lda     #>$c000+80
            sta     src+1
    
            lda     #<$c000
            sta     dest+0
            lda     #>$c000
            sta     dest+1
            
          ; Round X up to the next whole number of pages.
          ; Slight overkill, but keeps the code simple.
            ldx     #>(80*60)+256
            ldy     #0
_loop  
            lda     (src),y
            sta     (dest),y
            iny
            bne     _loop
            inc     src+1
            inc     dest+1
            dex
            bne     _loop
            
            rts

            .send
            .endn
