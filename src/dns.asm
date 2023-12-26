; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

dns         .namespace

            .section    dp
name_len    .byte       ?   ; length of the name.
name_addr   .word       ?   ; address of the name.
            .send

            .section    data
socket      .fill       32
token_len   .byte       ?
cookie      .byte       ?
type        .byte       ?
class       .byte       ?
data        .byte       ?
ip          .dword      ?   ; address in network order.
            .send            

            .section    pages
request     .dstruct    header
            .align      256
response    .dstruct    header
            .align      256
            .send

            .section    code


header      .struct
id          .word       ?
flags       .word       ?
            .byte       ?
qdcount     .byte       ?
            .byte       ?
ancount     .byte       ?
            .byte       ?
nscount     .byte       ?
            .byte       ?
arcount     .byte       ?
data        .ends



lookup
            jsr     _try
            bcc     _done
            jsr     _try
            bcc     _done
            jsr     _try
            bcc     _done
            jsr     _try
            bcc     _done
            jsr     _try
            bcc     _done
            jsr     _try
_done
            rts            
_try            
            jsr     init_request

          ; Randomish id.
            lda     #kernel.args.timer.FRAMES | kernel.args.timer.QUERY
            sta     kernel.args.timer.units
            jsr     kernel.Clock.SetTimer
            sta     cookie
            sta     request.id
            
            lda     #1  ; Recursive
            sta     request.flags

            lda     #1  ; One name, one arg.
            sta     request.qdcount

            ldx     #header.data
            jsr     append_query

            jsr     dump_request

            txa
            jsr     send
            bcs     _done

            ;lda     #13
            ;jsr     putchar
            jmp     recv
                    

dump_request
    rts
            phx
            ldy     #0
_loop
            lda     request,y
            jsr     print_byte
            iny
            dex
            bne     _loop
            plx
            rts

init_request
            phx
            ldx     #0
_loop       
            stz     request,x     
            inx
            cpx     #header.data
            bne     _loop

            plx
            clc
            rts

append_query
            jsr     encode_name
            bcs     _out

            lda     #1  ; query type: host address
            stz     request,x
            inx
            sta     request,x
            inx

            lda     #1  ; entry class IN (internet)
            stz     request,x
            inx
            sta     request,x
            inx
_out
            rts

parse_response
            ldx     #header.data
_queries
            lda     response.qdcount
            beq     _answers
            jsr     parse_query
            dec     response.qdcount
            bne     _queries 
_answers
            lda     response.ancount
            sec
            beq     _out
            jsr     parse_answer
            bcs     _out
            lda     type
            cmp     #1
            bne     _next
            lda     class
            cmp     #1
            beq     _addr
_next
            dec     response.ancount
            bra     _answers           
            
_addr
            ldx     data
            lda     response+0,x
            sta     ip+0
            lda     response+1,x
            sta     ip+1
            lda     response+2,x
            sta     ip+2
            lda     response+3,x
            sta     ip+3
            clc
_out
            rts            


parse_query
            jsr     parse_name
            bcs     _out
            
            inx
            inx
            inx
            inx
            clc
_out
            rts
            
parse_answer
            jsr     parse_name
            bcs     _out

          ; Type
            inx
            lda     response,x
            sta     type
            inx

          ; Clas
            inx
            lda     response,x
            sta     class
            inx

          ; ttl
            inx
            inx
            inx
            inx

          ; Data size
            lda     response,x
            cmp     #1
            bcs     _out
            inx
            inx
            stx     data
            txa
            adc     response-1,x
            tax
_out
            rts            
                        
            
parse_name
    ; IN:   X points to the start of a name.
    ; OUT:  X points past the end of the name.
    
_loop
            lda     response,x
            beq     _finish
            cmp     #$c0
            beq     _tail
            bcs     _out
            txa
            sec
            adc     response,x
            tax
            bra     _loop
_tail
            inx
_finish
            inx
            clc
_out            
            rts                        
            
            

encode_name
    ; IN:   name_addr and name_len initialized.
    ;       X contains the dest offset.
    ;
    ; OUT:  X is advanced to the next free byte.
    ;       Carry set on empty name; cleared otherwise.
    
            lda     name_len
            bne     +
            sec
            rts
+
            phy
            ldy     #0
_loop
            jsr     token_length
            beq     _close
            
            sta     token_len
            sta     request,x
            inx
_copy
            lda     (name_addr),y
            sta     request,x
            inx                     
            iny
            dec     token_len
            bne     _copy
            cpy     name_len
            bcs     _close
            iny
            bra     _loop
_close
            stz     request,x
            inx
            ply
            clc
            rts  
           

token_length
    ; IN:   Y = offset of next token in name.
    ; OUT:  A = length of the token at Y.
    ;       Carry clear; Z set if A is zero.
    
            phx
            phy
            bra     _next
_loop
            lda     (name_addr),y
            cmp     #'.'
            beq     _done
            iny
_next
            cpy     name_len
            bne     _loop
_done
            tya
            tsx
            sbc     $101,x
            
            ply
            plx
            ora     #0
            clc
            rts            

open
          ; Mount the socket.
            lda     #<socket
            sta     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1

          ; A Google resolver.
            lda     #8
            sta     kernel.args.net.dest_ip+0
            sta     kernel.args.net.dest_ip+1
            sta     kernel.args.net.dest_ip+2
            sta     kernel.args.net.dest_ip+3

          ; Randomish local port (1024+frame count).
            lda     #kernel.args.timer.FRAMES | kernel.args.timer.QUERY
            sta     kernel.args.timer.units
            jsr     kernel.Clock.SetTimer
            sta     kernel.args.net.src_port+0
            lda     #$4
            sta     kernel.args.net.src_port+1

          ; Remote port in host order (little-endian).
            lda     #53
            sta     kernel.args.net.dest_port+0
            stz     kernel.args.net.dest_port+1

            jmp     kernel.Net.UDP.Init
    
send
            pha
            jsr     open
            pla
            bcc     +
            rts
+            
            sta     kernel.args.net.buflen

            lda     #<socket
            sta     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1

            lda     #<request
            sta     kernel.args.net.buf+0
            lda     #>request
            sta     kernel.args.net.buf+1
            
            jmp     kernel.Net.UDP.Send
            
recv
          ; Init the event buffer.
            lda     #<io.event
            sta     kernel.args.events.dest+0
            lda     #>io.event
            sta     kernel.args.events.dest+1

          ; Schedule a timer.
            lda     #kernel.args.timer.FRAMES | kernel.args.timer.QUERY
            sta     kernel.args.timer.units
            jsr     kernel.Clock.SetTimer 
            bcs     _out

            adc     #60
            sta     kernel.args.timer.absolute
            lda     #kernel.args.timer.FRAMES
            sta     kernel.args.timer.units
            lda     #name_len   ; TODO: just unique.
            sta     kernel.args.timer.cookie
            jsr     kernel.Clock.SetTimer 
            bcs     _out
            
            jmp     next_event
_out
            rts            
            
next_event
            bit     kernel.args.events.pending
            ;beq     _yield
    
            jsr     kernel.NextEvent
            bcs     _yield
            
            lda     io.event.type

            cmp     #kernel.event.net.UDP
            beq     udp

            cmp     #kernel.event.timer.EXPIRED
            beq     _timer

_yield
      ; This is optional, but the kernel will need time to
      ; process IP traffic, so if we have nothing better to
      ; do, giving the kernel the rest of our time is nice.

            jsr     kernel.Yield
            bra     next_event
        
_timer
            lda     io.event.timer.cookie
            cmp     #name_len   ; TODO...
            bne     next_event
            sec
_out
            rts
            
udp
            lda     #<socket
            sta     kernel.args.net.socket+0
            lda     #>socket
            sta     kernel.args.net.socket+1
            
          ; If the data received isn't for our socket,
          ; ignore it.
          ; TODO: is the wifi NAT wonking DNS?
            jsr     kernel.Net.Match
            ;bcs     next_event

            lda     #<response
            sta     kernel.args.net.buf+0
            lda     #>response
            sta     kernel.args.net.buf+1
            lda     #$ff
            sta     kernel.args.net.buflen
            jsr     kernel.Net.UDP.Recv
            bcs     _out

            jsr     dump_response
            
          ; Check for ID match.
            lda     response.id
            eor     cookie
            adc     #$ff
            bcs     _out

            jsr     parse_response
            bcs     _out
            
.if false
            lda     ip+0
            jsr     print_byte
            lda     ip+1
            jsr     print_byte
            lda     ip+2
            jsr     print_byte
            lda     ip+3
            jsr     print_byte
.endif            
_out            
            rts

dump_response
    clc
    rts
            phx
            ldx     #0
_loop      
            lda     response,x
            jsr     print_byte
            inx
            cpx     kernel.args.net.accepted
            bne     _loop     
            plx       
            lda     #13
            jsr     putchar
            clc
            rts

    
print_dns
    clc
    rts
            ldy     #0
_loop
            lda     (dns.name_addr),y
            jsr     putchar
            iny
            cpy     dns.name_len
            bne     _loop
            clc
            rts
            
            .send
            .endn
            

