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

*           = $0200
            .dsection   pages
            .dsection   data

*           = $a000     ; Application start.
start
            .text       $f2,$56     ; Signature
            .byte       1           ; 1 block
            .byte       5           ; mount at $a000
            .word       wget.run    ; Start here
            .word       0           ; version
            .word       0           ; kernel
            .text       "wget",0

            .dsection   code
            .align      256
Strings     .dsection   strings

wget        .namespace

            .section    code

url         
            .text       "http://www.tim.org/demo.pgz"
url_end
            .text       "http://www.hackwrenchlabs.com/hello.pgz"
            .text       "http://songseed.org/cosmic-1111.pgz"
run
          ; trash our signature.
            stz     start

          ; Init the screen.
            jsr     display.screen_init

          ; Init the io subsystem.
            jsr     io.init
	
          ; Set http.url.
            lda     #<url
            sta     http.url+0
            lda     #>url
            sta     http.url+1
            lda     #url_end - url
            sta     http.url_len

          ; Set http.accept.
            lda     #<pgz.accept
            sta     http.accept+0
            lda     #>pgz.accept
            sta     http.accept+1

          ; Init HTTP with the request.
            jsr     http.init


          ; Try to download the data
            jsr     try
            bcc     _exec
            jsr     try
            bcc     _exec
            jsr     try
            bcc     _exec
            
_done
            bcs     error
            rts

_exec
          ; Start the downloaded program!
            jmp     pgz.exec

try
          ; Init the accept state machine.
            jsr     pgz.init

          ; Make the request
            jmp     http.perform_request

error
            ldy     #0
_loop
            lda     _text,y
            beq     _done
            jsr     putchar
            iny
            bra     _loop
_done       bra     _done
_text       .null   "Error"                        

            .send
            .endn
        
