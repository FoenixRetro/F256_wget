; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

            .namespace  io
tcp         .namespace            

            .section    dp
port        .word       ?            
eof         .byte       ?
frame       .byte       ?   ; Frame for next timer event.
state       .byte       ?   ; Zero if not connected.
rx_received .byte       ?
rx_accepted .byte       ?
tx_len      .byte       ?
tx_sent     .byte       ?
            .send
            
            .section    pages
rx_buf      .fill       256  
tx_buf      .fill       256      
socket      .fill       256
            .send

            .section    code
open
    ; IN:   dns.ip contains the address; port contains the port.

          ; Register our event handlers.

            ldx     #kernel.event.net.TCP
            lda     #<tcp
            sta     io.handlers+0,x
            lda     #>tcp
            sta     io.handlers+1,x

            ldx     #kernel.event.timer.EXPIRED
            lda     #<timer
            sta     io.handlers+0,x
            lda     #>timer
            sta     io.handlers+1,x

          ; Not connected yet.
            lda     #STATE.CLOSED
            sta     state

          ; Bytes are expected.
            lda     #0
            sta     eof
            sta     tx_sent
            sta     rx_received
            sta     rx_accepted

            jsr     tcp_open
            bcs     _out

          ; Schedule the first timer event.
            lda     #kernel.args.timer.FRAMES | kernel.args.timer.QUERY
            sta     kernel.args.timer.units
            jsr     kernel.Clock.SetTimer
            sta     frame
            jsr     timer_schedule

            clc
_out
            rts
            
tcp_open

          ; Give the kernel 256 bytes at 'socket' for
          ; tracking the state of this connection.
            stz     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1
            lda     #255
            sta     kernel.args.buflen
            
          ; Randomish local port (2048+frame count).
            lda     #kernel.args.timer.FRAMES | kernel.args.timer.QUERY
            sta     kernel.args.timer.units
            jsr     kernel.Clock.SetTimer
            sta     kernel.args.net.src_port+0
            lda     #$8
            sta     kernel.args.net.src_port+1

          ; Set remote port.
            lda     port+0
            sta     kernel.args.net.dest_port+0
            lda     port+1
            sta     kernel.args.net.dest_port+1
            
          ; Copy dest IP from DNS.
            ldy     #3
_loop
            lda     dns.ip,y
            sta     kernel.args.net.dest_ip,y
            dey
            bpl     _loop

            jmp     kernel.Net.TCP.Open

timer_schedule

          ; Compute the time for the next event.
            lda     frame
            clc
            adc     #60
            sta     frame
    
          ; Schedule the timer.
            lda     #kernel.args.timer.FRAMES
            sta     kernel.args.timer.units
            lda     frame
            sta     kernel.args.timer.absolute
            lda     #port   ; TODO: just unique
            sta     kernel.args.timer.cookie
_retry  
            jsr     kernel.Clock.SetTimer
            bcc     _done
            jsr     kernel.Yield
            bra     _retry
_done
            rts


read_byte
            phx
            phy
_loop            
            ldx     rx_accepted
            cpx     rx_received
            bcc     _data
            
            lda     eof
            bne     _done

            lda     #0
            sta     rx_accepted
            sta     rx_received
            jsr     next_event
            bra     _loop

_data
            lda     rx_buf,x
            inc     rx_accepted
_done
            ply
            plx
            rts

timer
            lda     io.event.timer.cookie
            eor     #port   ; TODO...
            bne     _out

            lda     eof
            bne     _done

            lda     state
            cmp     #STATE.ESTABLISHED
            beq     _push
            
            lda     #1
            sta     eof
            rts

_push
          ; Try to push an empty packet to force a retransmit.
          ; The modern internet barely needs this, but your
          ; wifi may be particularly bad...
            ;jsr     tcp_push
    
          ; Schedule the next event
            jmp     timer_schedule
_done
_out
            rts

tcp_push
    ; Push an empty buffer.  This will keep NATs from
    ; dropping connections, and will help with crappy
    ; wifi conditions.  In theory, the internet is lossy;
    ; in practice, it rarely misses a beat.
    
            lda     state
            eor     #STATE.ESTABLISHED
            beq     _push
            rts
_push            
            lda     #0
            jmp     tcp_send

tcp_send:
    ; A = # of bytes (from tx_buf) to send.
    
          ; Set the # of bytes in the buffer.
            sta     kernel.args.net.buflen

          ; Set the socket.
            lda     #<socket
            sta     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1
    
          ; Set the buffer pointer.
            lda     tx_sent
            sta     kernel.args.net.buf+0
            lda     #>tx_buf
            sta     kernel.args.net.buf+1
    
          ; Send the data!
            jsr     kernel.Net.TCP.Send
            bcs     +
            lda     kernel.args.net.accepted
            beq     +
            adc     tx_sent
            sta     tx_sent

.if false
    phx
    ldx #0
_l  lda tx_buf,x
    lda #'x'
    jsr putchar
    inx
    cpx kernel.args.net.accepted
    bne _l
    clc    
    plx
.endif
            clc
+
            rts            

tcp
    ; Receive and display TCP data.
        
          ; Use our (hopefully) open socket.
            lda     #<socket
            sta     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1
    
          ; If the data received isn't for our socket,
          ; ignore it.
            jsr     kernel.Net.Match
            bcs     _reject
    
          ; Receive the data into our buffer.
          ; TODO: safe to extend the buffer a little.
            lda     #<rx_buf
            sta     kernel.args.net.buf+0
            lda     #>rx_buf
            sta     kernel.args.net.buf+1
            lda     #$ff
            sta     kernel.args.net.buflen
    
            jsr     kernel.Net.TCP.Recv
            bcs     _out

          ; Dispatch based on state.
            cmp     #STATE.ESTABLISHED
            beq     _established
            cmp     #STATE.CLOSED
            beq     _closed
_out
            rts

_established

          ; Were we already established?
            cmp     state
            beq     _read

          ; Save the new state.
            sta     state

          ; Start sending the request.
            lda     tx_len
            sec
            sbc     tx_sent
            jmp     tcp_send

_read
          ; Accept any bytes.
            lda     kernel.args.net.accepted
            sta     rx_received
            jsr     dump_buf

          ; Send any unsent bytes.
            lda     tx_sent
            sec
            sbc     tx_len
            beq     _done
            jsr     tcp_send

_done
            clc
            rts

_closed
            sta     state
            jsr     _read
            ;jsr     print_closed
            
            lda     #1
            sta     eof
            rts
            
_reject
            jmp     kernel.Net.TCP.Reject


print_closed
            lda     #13
            jsr     putchar
            phy
            ldy     #0
_loop       lda     _msg,y
            beq     _done
            jsr     putchar
            iny
            bra     _loop
_done       lda     #13
            jsr     putchar
            ply
            rts   
_msg        .text   "CLOSED",13,0


dump_buf rts
            ldx     #0
_loop       
            cpx     rx_received
            beq     _done
            lda     rx_buf,x
            phx
            jsr     putchar
            plx
            inx
            bra     _loop
_done
            lda     #'!'
            jmp     putchar
            rts                        

        
tcp_close
            lda     state
            cmp     #STATE.ESTABLISHED
            beq     +
            rts
+
          ; Close the socket.
          ; TODO: wait for completion or timeout.
            lda     #<socket
            sta     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1
            jmp     kernel.Net.TCP.Close            



states
            .dstruct    STATE

                  ; TCP states, from RFC793...
STATE               .struct
CLOSED              .word   str_closed
LISTEN              .word   str_listen
SYN_SENT            .word   str_syn_sent
SYN_RECEIVED        .word   str_syn_received
ESTABLISHED         .word   str_established
FIN_WAIT_1          .word   str_fin_wait_1
FIN_WAIT_2          .word   str_fin_wait_2
CLOSE_WAIT          .word   str_close_wait
CLOSING             .word   str_closing
LAST_ACK            .word   str_last_ack
TIME_WAIT           .word   str_time_wait
                    .ends

str_closed          .null   "closed       "
str_listen          .null   "listen       "
str_syn_sent        .null   "syn_sent     "
str_syn_received    .null   "syn_received "
str_established     .null   "established  "
str_fin_wait_1      .null   "fin_wait_1   "
str_fin_wait_2      .null   "fin_wait_2   "
str_close_wait      .null   "close_wait   "
str_closing         .null   "closing      "
str_last_ack        .null   "last_ack     "
str_time_wait       .null   "time_wait    "


            .send
            .endn            
            .endn            
