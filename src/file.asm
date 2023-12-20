; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

file        .namespace

            .section    dp
fname       .word       ?
fname_len   .byte       ?
rx_buf      .word       ?
tx_buf      .word       ?
            .send
            
PAGES       =   8
            .section    pages
pages       .fill       PAGES*256
            .send

            .section    data
head        .byte       ?   ; Alloc pages here.
tail        .byte       ?   ; Consume pages from here.
stream      .byte       ?   ; Open file handle.
state       .byte       ?   ; File status.
rx_len      .byte       ?   ; Bytes in current rx buffer.
writing     .byte       ?   ; Non-zero if writing.
closing     .byte       ?   ; Non-zero if closing.
            .send            

            .section    code            

open
    ; Called by http.
    ; IN:   fname/len initialized.
    ; OUT:  carry set to open status.

          ; File not open yet.
            stz     state
            stz     writing
            stz     closing
            
          ; Init the buffer queue.
            stz     head
            stz     tail
            stz     rx_buf+1
            stz     tx_buf+1

          ; Register our file event handlers.

            ldx     #kernel.event.file.OPENED
            lda     #<handle_opened
            sta     io.handlers+0,x
            lda     #>handle_opened
            sta     io.handlers+1,x

            ldx     #kernel.event.file.WROTE
            lda     #<handle_wrote
            sta     io.handlers+0,x
            lda     #>handle_wrote
            sta     io.handlers+1,x

            ldx     #kernel.event.file.CLOSED
            lda     #<handle_closed
            sta     io.handlers+0,x
            lda     #>handle_closed
            sta     io.handlers+1,x

            ldx     #kernel.event.file.ERROR
            lda     #<handle_error
            sta     io.handlers+0,x
            lda     #>handle_error
            sta     io.handlers+1,x

          ; Open the file
            jmp     open_file

open_file
          ; Set the drive; only the SDC is fast enough.
            stz     kernel.args.file.open.drive

          ; Set the fname and len.
            lda     fname+0
            sta     kernel.args.file.open.fname+0
            lda     fname+1
            sta     kernel.args.file.open.fname+1
            lda     fname_len
            sta     kernel.args.file.open.fname_len
            
          ; Set the mode.  For now, always overwrite.
            lda     #1
            sta     kernel.args.file.open.mode

          ; Set the cookie (not used)
            stz     kernel.args.file.open.cookie
            
          ; Submit the request
            jsr     kernel.File.Open
            bcs     _out
            sta     stream
            
          ; Wait for the operation to complete.
_loop
            jsr     io.next_event
            lda     state
            beq     _loop
            
            cmp     #kernel.event.file.ERROR
            beq     _out
            cmp     #kernel.event.file.OPENED
            bne     _loop            
            clc
_out
            rts

handle_opened
handle_closed
handle_error
            lda     io.event.file.stream
            cmp     stream
            bne     +
            stx     state
+
            clc
            rts

accept
    ; Called by http.
    ; Returns w/ carry set on error.
    ; IN:   A contains the byte to write.

            phy
.if false
   pha
   jsr putchar
   pla
.endif

          ; Make sure we have a buffer.
            ldy     rx_buf+1
            bne     +
            pha
            jsr     alloc
            pla
            bcs     _out
+
          ; Append the byte to the buffer
            ldy     rx_len
            sta     (rx_buf),y
            iny
            sty     rx_len
            
          ; If the buffer is full, enque it.
            cpy     #255
            bne     _out
            jsr     enque
            stz     rx_buf+1
_out
            ply
            rts

alloc
            lda     head
            inc     a
            and     #PAGES-1
            cmp     tail
            beq     _out
            lda     head
            clc
            adc     #>pages
            stz     rx_buf+0
            sta     rx_buf+1
            stz     rx_len
            clc
_out
            rts

enque
            phy
            
          ; Stash the buflen.
            lda     rx_len
            ldy     #255
            sta     (rx_buf),y

          ; Mark the buffer as writable.
            lda     head
            inc     a
            and     #PAGES-1
            sta     head

          ; If we aren't writing, better start.
            lda     writing
            bne     _out    
            jsr     deque   
            lda     (tx_buf),y
            jsr     write
_out
            ply
            rts

deque
            lda     tail
            cmp     head
            beq     _out
            stz     tx_buf+0
            clc
            adc     #>pages
            sta     tx_buf+1
_out
            rts                        
            

write
            sta     kernel.args.file.write.buflen
            lda     stream
            sta     kernel.args.file.write.stream
            lda     tx_buf+0
            sta     kernel.args.file.write.buf+0
            lda     tx_buf+1
            sta     kernel.args.file.write.buf+1

            sta     writing
            jmp     kernel.File.Write

handle_wrote

          ; Bail if this is someone else's stream.
            lda     io.event.file.stream
            cmp     stream
            bne     _out

          ; Did we write the whole buffer?
            lda     io.event.file.wrote.wrote
            cmp     io.event.file.wrote.requested
            beq     _next

          ; Try to write the remaining.
            clc
            adc     tx_buf
            sta     tx_buf
            lda     io.event.file.wrote.requested
            sec
            sbc     io.event.file.wrote.wrote
            jmp     write

_next
          ; Print the DL status
            jsr     http.print_remaining

          ; Try to write the next queued buffer.
            jsr     free
            jsr     deque
            bcc     _write
            stz     writing

          ; Are we done?
            lda     closing
            beq     _out
            jmp     file_close
_out
            clc
            rts       
_write
            phy
            ldy     #255
            lda     (tx_buf),y
            ply
            jmp     write

free
            lda     tail
            inc     a
            and     #PAGES-1
            sta     tail
            rts


close
    ; Called by wget when http is finished.

          ; If there's pending data, enque it.
            lda     rx_buf+1
            beq     +
            jsr     enque
+              
          ; If we're done writing, close.
            lda     writing
            bne     +
            jmp     file_close
+            
          ; Still writing, schedule the close and wait.
            inc     closing
            jmp     wait_closed

file_close
            lda     stream
            sta     kernel.args.file.close.stream
            jsr     kernel.File.Close
            bcc     wait_closed
            rts

wait_closed
_loop
            jsr     io.next_event
            lda     state
            cmp     #kernel.event.file.CLOSED
            bne     _loop
            clc
            rts

            .send
            .endn
            
