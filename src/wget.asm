; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

*           = $0000     ; Kernel Direct-Page
mmu_ctrl    .byte       ?
io_ctrl     .byte       ?
reserved    .fill       6
mmu         .fill       8
            .dsection   dp
            .cerror * > $00ff, "Out of dp space."

*           = $2000
            .dsection   pages
            .dsection   data

*           = $a000     ; Application start.
start
            .text       $f2,$56     ; Signature
            .byte       1           ; 1 block
            .byte       5           ; mount at $a000
            .word       wget.run    ; Start here
            .byte       1           ; structure version
            .byte       0           ; reserved
            .byte       0           ; reserved
            .byte       0           ; reserved
            .text       "wget",0
            .text       0
usage       .null       "wget url [filename]"

            .dsection   code
            .align      256
Strings     .dsection   strings

wget        .namespace

            .section    dp
argc        .byte       ?
argv        .word       ?
            .send

            .section    code

run
          ; trash our signature.
            stz     start

          ; Init the screen.
            jsr     display.screen_init
            jsr     banner

          ; Validate argc and save.
            lda     kernel.args.extlen
            lsr     a
            beq     _help
            dec     a
            beq     _help
            sta     argc 
            cmp     #3
            bcs     _help            

          ; Copy the argv ptr before it can get trashed.
            lda     kernel.args.ext+0
            sta     argv+0
            lda     kernel.args.ext+1
            sta     argv+1

          ; Init the io subsystem.
            jsr     io.init

          ; Set http.url.
            jsr     set_url
            bcs     _failed

          ; Set the file name.
            jsr     set_filename
            bcs     _failed
            jsr     draw_filename

          ; Set http.accept.
            lda     #<file.accept
            sta     http.accept+0
            lda     #>file.accept
            sta     http.accept+1

          ; Init HTTP with the request.
            jsr     http.init
            bcs     _failed

          ; Try to download the data
            jsr     try
            bcc     success
            jsr     try
            bcc     success
            jsr     try
            bcc     success

_failed
            jmp     error
_help
            ldy     #0
_loop       lda     usage,y
            beq     _failed
            jsr     putchar
            iny
            bra     _loop            
            
try
          ; Open the file
            jsr     file.open
            bcc     +
            rts
+            
          ; Make the request
            jsr     http.perform_request
            php
            jsr     file.close
            plp
            
            rts

success
            lda     #12
            clc
            adc     file.fname_len
            sta     display.cursor
            
            ldy     #0
_loop                        
            lda     _msg,y
            beq     _done
            jsr     putchar
            iny
            bra     _loop
_done       jmp     end
_msg        .text   "Success!"
            .null   "  Press any key to continue."
            
error
            ldy     #0
_loop
            lda     _text,y
            beq     _done
            jsr     putchar
            iny
            bra     _loop
_done       jmp     end
_text       .text   "Failed."
            .null   "  Press any key to continue."

end
            jsr     kernel.NextEvent
            bcs     end
            lda     io.event.type
            cmp     #kernel.event.key.PRESSED
            bne     end

            lda     #$41
            sta     kernel.args.run.block_id
            jmp     kernel.RunBlock

set_url
          ; Copy the arg.
            ldy     #2
            lda     (argv),y
            sta     http.url+0
            iny
            lda     (argv),y
            sta     http.url+1

          ; Compute the length
            ldy     #0
_ulen       lda     (http.url),y
            beq     +
            ;jsr     putchar
            iny
            bra     _ulen
+           cpy     #0
            beq     _out
            sty     http.url_len
            
          ; Find the last slash.
            lda     #'/'
            bra     _next
_slash
            cmp     (http.url),y
            beq     _found
_next
            dey
            bne     _slash
            sec
_out            
            rts

_found
          ; Verify that there's a slash
          ; after the protocol prefix.
            cpy     #7  ; http://
            bcc     _fix
            clc
            rts
_fix
          ; Append a slash
            ldy     http.url_len
            sta     (http.url),y
            inc     http.url_len
            clc
            rts                    
                        
set_filename

          ; If no name is provided, parse it from the URL.
            lda     argc
            dec     a
            beq     parse_filename

          ; Init the name from the arg array.
            ldy     #4
            lda     (argv),y
            sta     file.fname+0
            iny
            lda     (argv),y
            sta     file.fname+1

          ; Compute the size.
            ldy     #0
_loop       lda     (file.fname),y
            beq     _done
            ;jsr     putchar
            iny
            bra     _loop
_done       sty     file.fname_len
            clc
            rts
                                    

parse_filename
    ; IN:   url/end
    ; OUT:  file.fname/len initialized.

          ; Y = length
            ldy     http.url_len

          ; If the URL ends with a '/',
          ; use 'index.html'.
            lda     #'/'
            dey
            cmp     (http.url),y
            beq     _index
            bra     _next
_loop
            cmp     (http.url),y
            beq     _found
_next       dey
            bne     _loop
            sec
_out
            rts
_found            
            iny
            tya
            clc
            adc     http.url+0
            sta     file.fname+0
            lda     http.url+1
            adc     #0
            sta     file.fname+1

            sty     file.fname_len
            lda     http.url_len
            sec
            sbc     file.fname_len
            sta     file.fname_len
            clc
            rts
            
_index
            lda     #<(index_html+1)
            sta     file.fname+0
            lda     #>(index_html+1)
            sta     file.fname+1
            lda     index_html
            sta     file.fname_len
            clc
            rts

index_html  .ptext  "index.html"

banner
            jsr     cls
            ldy     #0
_loop1      lda     _msg1,y
            beq     _done1
            sta     $c000+80*0,y
            iny
            bra     _loop1
_done1
            ldy     #0
_loop2      lda     _msg2,y
            beq     _done2
            sta     $c000+80*1,y
            iny
            bra     _loop2
_done2

            clc
            rts
_msg1       .null   "WGET 1.0 Copyright 2023 Jessie Oberreuter, GPL3."
_msg2       .null   "Like this? Please Paypal $10 to joberreu@moselle.com. Thanks!"

cls
            lda     #3
            sta     io_ctrl
            lda     $c000
            jsr     _fill
            
            lda     #2
            sta     io_ctrl
            lda     #32
            
_fill
            ldy     #0
_loop        
            sta     $c000+0*80,y
            sta     $c000+1*80,y
            sta     $c000+2*80,y
            sta     $c000+3*80,y
            sta     $c000+4*80,y
            iny
            cpy     #80
            bne     _loop

            clc
            rts
            
draw_filename
            ldy     #0
_loop
            lda     (file.fname),y
            beq     _done
            sta     $c00a+80*3,y
            iny
            cpy     file.fname_len
            bne     _loop
_done
            clc
            rts            
            

            .send
            .endn
        
