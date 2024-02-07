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

*           = $8000     ; Application start.
start
            .text       $f2,$56     ; Signature
            .byte       1           ; 1 block
            .byte       4           ; mount at $8000
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
relpath     .byte       ?   ; Start of prefix-relative path.
            .send

            .section    pages
path        .fill       256
            .send

            .section    code

run
          ; trash our signature.
            stz     start

          ; Init the io subsystem.
            jsr     io.init


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

          ; Init the URL from args.
            jsr     set_url_from_arg
            bcs     _failed

          ; Set http.accept.
            lda     #<file.accept
            sta     http.accept+0
            lda     #>file.accept
            sta     http.accept+1

          ; Set up the request.
            jsr     prepare_http_request
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
 lda #'t'
 jsr putchar
 lda #'r'
 jsr putchar
 lda #'y'
 jsr putchar
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
            bcc     _out

          ; Did we fail because of a redirect?
            lda     http.redirect_length
            beq     _out

          ; Retry following the redirect.
            lda     #<http.redirect
            sta     http.url+0
            lda     #>http.redirect
            sta     http.url+1
            lda     http.redirect_length
            sta     http.url_len
            jsr     prepare_http_request
            sec
_out
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
_text       .text   "  Failed."
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

prepare_http_request

          ; Normalize the URL.
            jsr     normalize_url
            bcs     _out

          ; Set the file name.
            jsr     set_filename
            bcs     _out
            jsr     draw_filename

          ; Init HTTP with the request.
            jsr     http.init
_out
            rts


set_url_from_arg

          ; Copy the arg.
            ldy     #2
            lda     (argv),y
            sta     http.url+0
            iny
            lda     (argv),y
            sta     http.url+1

          ; Full request?
            jsr     _length
            jsr     http.is_url
            beq     +
            jsr     prefix
            bcs     _out
+
          ; Compute the length
_length
            ldy     #0
_ulen       lda     (http.url),y
            beq     +
            iny
            bra     _ulen
+           cpy     #0
            beq     _out
            sty     http.url_len
            clc
_out
            rts

normalize_url

            ldy     http.url_len

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
_msg1       .null   "WGET 1.2 Copyright 2023 Jessie Oberreuter."
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

prefix
    ; IN:   http_url -> file path
    ; OUT:  http_url -> url, url_len set.
    ;       Carry set on error.

    ; Path starts with a filename.
    ; Parse it out, read the file,
    ; and prefix the path with the
    ; file's contents.

            jsr     find_path
            bcs     _out
            sty     relpath
            jsr     read_path
            bcs     _out
            jsr     find_end
            bcs     _out
            jsr     append_url
_out
            rts

find_path
            ldy     #0
_loop
            lda     (http.url),y
            beq     _out
            sta     path,y
            eor     #'/'
            beq     _out
            iny
            bne     _loop
            sec
_out
            rts

read_path
    ; IN:   path contains the filename; Y=len.
    ; OUT:  Y = prefix length, or carry set on error.

          ; Allocate space on the stack for the data length.
            phx
            phy
            tsx

          ; Set the drive; only the SDC is fast enough.
            stz     kernel.args.file.open.drive

          ; Set the fname and len.
            lda     #<path
            sta     kernel.args.file.open.fname+0
            lda     #>path
            sta     kernel.args.file.open.fname+1
            sty     kernel.args.file.open.fname_len

          ; Set the mode.  For now, always overwrite.
            lda     #kernel.args.file.open.READ
            sta     kernel.args.file.open.mode

          ; Set the cookie (not used)
            stz     kernel.args.file.open.cookie

          ; Submit the request
            jsr     kernel.File.Open
            bcs     _out
            sta     kernel.args.file.read.stream

          ; Wait for the operation to complete.
            lda     #kernel.event.file.OPENED
            jsr     file_wait
            bcs     _out

          ; Read the first chunk of the file.
            lda     #$ff
            sta     kernel.args.file.read.buflen
            jsr     kernel.File.Read
            bcs     _close

          ; Wait for the operation to complete.
          ; Should normally loop but (cheating),
          ; I know this program only works with fat32,
          ; which always reads fully.
            lda     #kernel.event.file.DATA
            jsr     file_wait
            bcs     _close

          ; Stash the # of bytes read.
            lda     io.event.file.data.read
            sta     $101,x

          ; Copy the data (reusing 'path')
            sta     kernel.args.recv.buflen
            lda     #<path
            sta     kernel.args.recv.buf+0
            lda     #>path
            sta     kernel.args.recv.buf+1
            jsr     kernel.ReadData
            clc
_close
            php     ; Might have gotten here on an error.
            jsr     kernel.File.Close
            bcs     +
            lda     #kernel.event.file.CLOSED
            jsr     file_wait
+           plp

_out
            ply
            plx
            rts



file_wait
    ; Waits for a file event.
    ; Carry clear if the event is the expected event.
    ; IN:   A = expected event.

            phx
            pha
            tsx
_loop
            jsr     kernel.NextEvent
            bcs     _loop
            lda     io.event.type
            cmp     #kernel.event.file.NOT_FOUND
            bcc     _loop
            cmp     #kernel.event.file.SEEK+2
            bcs     _loop
            eor     $101,x
            beq     _out
_fail
            sec
_out
            pla
            plx

            lda     io.event.type
            rts

find_end
    ; IN:   path loaded, Y=length.
    ; OUT:  y = trimmed length.

            phx
            phy
            tsx

          ; The path needs to be at least long enough
          ; to be an http://<host> string.
            lda     #10
            cmp     $101,x
            bcs     _out

            ldy     #0
_loop
            lda     path,y
            cmp     #33
            bcc     _out
            iny
            beq     _out
            tya
            cmp     $101,x
            bne     _loop
            clc
_out
            pla
            plx
            rts

append_url
    ; IN:   Y = path end, relpath = start of relative path.

            phx
            tya
            tax
            ldy     relpath
_loop
            lda     (http.url),y
            beq     _export
            sta     path,x
            inx
            beq     _fail
            iny
            beq     _fail
            bra     _loop
_fail
            sec
            bra     _out
_export
            lda     #0
            sta     path,x
            lda     #<path
            sta     http.url+0
            lda     #>path
            sta     http.url+1
            stx     http.url_len
            clc
_out
            plx
            rts

            .send
            .endn
