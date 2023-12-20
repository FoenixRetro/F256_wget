; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

                .cpu    "65c02"

http            .namespace

                .section    dp
url             .word       ?
url_len         .byte       ?

ptr             .word       ?
read_size       .dword      ?
block_size      .dword      ?
                .send
            
                .section    data
accept          .word       ?   ; Send body bytes here.
arg_offset      .byte       ?
compare_length  .byte       ?
line_length     .byte       ?
path_end        .byte       ?
path_offset     .byte       ?
                .send                

                .section    pages
line            .fill       256
                .send                

                .section    strings
http0           .ptext      "http/1.0 200 ok",$0d,$0a
http1           .ptext      "http/1.1 200 ok",$0d,$0a
content_length  .ptext      "content-length:"
                .send

            .section    code

init
          ; Generate the request.
            jsr     request
            bcs     _out

          ; Look up the IP for the server.
            jsr     dns.lookup
            bcs     _out

          ; Print the request info.
.if false
            jsr     print_cr
            jsr     dns.print_dns
            jsr     print_cr
            jsr     http.print_path
            jsr     print_cr
            jsr     http.print_request
.endif                        
          ; Set the port.
            lda     #80
            sta     io.tcp.port+0
            stz     io.tcp.port+1
            
            clc
_out
            rts            

request
    ; IN:   url/len -> URL
    ; OUT:  io.tx_buf filled with http request.

            jsr     parse_url
            bcs     _out
            
            ldx     #0
            jsr     append_get
            jsr     append_host
            stx     io.tcp.tx_len
            clc
_out            
            rts
            
append_get
            ldy     #0
_loop
            lda     _text,y
            beq     _done
            cmp     #'$'
            beq     _insert
            sta     io.tcp.tx_buf,x
            inx
_next            
            iny
            bne     _loop
_done
            clc
            rts
_insert
            jsr     insert_path
            jmp     _next
_text       .text   "GET $ HTTP/1.1",$0d,$0a,0                        

insert_path
            tya
            pha
            
            ldy     path_offset
_loop
            lda     (url),y
            sta     io.tcp.tx_buf,x
            inx
            iny
            cpy     path_end            
            bne     _loop
            
            pla
            tay
            clc
            rts


append_host
            ldy     #0
_loop
            lda     _text,y
            beq     _done
            cmp     #'$'
            beq     _insert
            sta     io.tcp.tx_buf,x
            inx
_next            
            iny
            bne     _loop
_done
            clc
            rts
_insert
            jsr     insert_host
            jmp     _next
_text       .text   "Host: $:80",$0d,$0a
            .text   "Connection: close",$0d,$0a
            .text   $0d,$0a,0

insert_host
            tya
            pha
            
            ldy     #0
_loop
            lda     (dns.name_addr),y
            sta     io.tcp.tx_buf,x
            inx
            iny
            cpy     dns.name_len            
            bne     _loop
            
            pla
            tay
            clc
            rts


parse_url
    ; IN:   line/line_length populated with the URL.
    ; OUT:  dns name/length and path offset/end initialized.
    
          ; Verify that it starts with "http://".
            jsr     is_http
            sec
            bne     _out
            sty     dns.name_len    ; scratch

          ; Point DNS at the host name.
            tya
            clc
            adc     url+0
            sta     dns.name_addr+0
            lda     url+1
            adc     #0
            sta     dns.name_addr+1

          ; Find the length of the hostname.
_host
            lda     (url),y
            cmp     #':'
            beq     _colon
            cmp     #'/'
            beq     _slash
            iny
            cpy     url_len
            bne     _host
_colon
            bcs     _out
_slash
          ; Set dns.name_len
            tya
            sec
            sbc     dns.name_len
            sta     dns.name_len
            
          ; The rest of the string is the path.
            sty     path_offset
            lda     url_len
            sta     path_end
            
            clc
_out
            rts            


is_http
    ; IN:   ptr/len -> URL
    ; OUT:  y=end, carry clear, Z set on match.

            lda     _http
            cmp     url_len
            bcs     _out

            ldy     #0
_loop
            lda     (url),y
            jsr     tolower
            cmp     _http+1,y
            bne     _out
            iny
            cpy     _http
            bne     _loop
_out
            clc
            rts            
_http       .ptext  "http://"

tolower
            cmp     #'A'
            bcc     _out
            cmp     #'Z'+1
            bcs     _out
            eor     #$20
_out
            rts


perform_request
            jsr     io.tcp.open
            bcs     _out
            
            jsr     parse_http

            php
            jsr     io.tcp.tcp_close
            plp
_out
            rts            

parse_http
            jsr     parse_protocol
            bcs     _out

            jsr     parse_headers
            bcs     _out

            jsr     parse_body
_out            
            rts

parse_protocol
            jsr     read_line
            bcs     _out

            lda     line_length
            ldy     #<http1
            jsr     compare_line
            beq     _out
            
            lda     line_length
            ldy     #<http0
            jsr     compare_line
            beq     _out
            
            sec
_out
            rts            

compare_line
    ; IN:   A = length, Y -> pstring to compare.
    ; OUT:  Carry clear, Z set on match.
    
            cmp     Strings,y
            bne     _out

            sta     compare_length
            iny
            sty     ptr+0
            lda     #>Strings
            sta     ptr+1
            
            ldy     #0
_loop       
            lda     line,y
            jsr     tolower
            cmp     (ptr),y
            bne     _out
            iny
            cpy     compare_length
            bne     _loop
_out            
            clc
            rts

read_line
            ldy     #0
            sty     line_length
            sty     arg_offset
_loop
            jsr     io.tcp.read_byte
            bcs     _error

.if false
 pha
 jsr putchar
 pla
.endif

            sta     line,y
            iny
            beq     _over

            cmp     #':'
            bne     _next
            sty     arg_offset
_next
            cmp     #$0a
            bne     _loop            
            sty     line_length

            clc
            rts
_over
            sec
_error
            rts

parse_headers
_loop
            jsr     read_line
            bcs     _done

          ; Stop on empty line.
            lda     line_length
            eor     #2
            beq     _done

          ; If it's a content_length header,
          ; parse out the byte count.
            lda     arg_offset
            ldy     #<content_length
            jsr     compare_line
            bne     +
            ldx     #block_size
            jsr     parse_number
            jsr     print_number
+           nop
            
            jmp     _loop

_done
            rts

parse_number
    ; IN:   x -> dword, y = offset of colon in line buffer.

            jsr     zero_number
    
            ldy     arg_offset
            jsr     skip_spaces
            bcs     _done
_loop
            lda     line,y
            
            cmp     #'0'
            bcs     +
            eor     #$0d
            beq     _done
            bne     _error
+           cmp     #'9'+1
            bcs     _done

            jsr     append_number
            iny
            bne     _loop   ; always
_error
            sec
_done
            rts

zero_number
            lda     #0
            sta     0,x
            sta     1,x
            sta     2,x
            sta     3,x
            rts
            
skip_spaces
            clc
_loop            
            lda     line,y
            eor     #' '
            bne     _done
            iny
            bne     _loop
_done
            eor     #$2d
            bne     _out
            sec
_out
            rts            

append_number
            sec
            sbc     #'0'
            pha
            lda     #4
_loop
            asl     3,x
            rol     2,x
            rol     1,x
            rol     0,x
            sbc     #0
            bne     _loop
            
            pla
            ora     3,x
            sta     3,x
            rts                     

subtract_number
    ; IN:   lhs in x, rhs in y.
    ; OUT:  Z and N flags set appropriately.
    
            sec
            sed

            lda     3,x
            sbc     3,y
            sta     3,x
            
            lda     2,x
            sbc     2,y
            sta     2,x
            
            lda     1,x
            sbc     1,y
            sta     1,x
            
            lda     0,x
            sbc     0,y
            sta     0,x
            
            cld
            
            ora     1,x
            ora     2,x
            ora     3,x

            clc
            rts

print_number
            stz     display.cursor
            lda     0,x
            jsr     print_hex
            lda     1,x
            jsr     print_hex
            lda     2,x
            jsr     print_hex
            lda     3,x
            jsr     print_hex
            clc
            rts

parse_body
    ; TODO: read/write chunks.
    
            ldx     #read_size
            jsr     zero_number

            ldx     #block_size
            ldy     #read_size
            jsr     subtract_number
            beq     _done

            inc     read_size+3
_loop
            jsr     io.tcp.read_byte
            bcs     _done

            jsr     _accept
            bcs     _done

            ldx     #block_size
            ldy     #read_size
            jsr     subtract_number
            bne     _loop
_done
            php
            ldx     #block_size
            jsr     print_number
            plp
            rts            
_accept
            jmp     (accept)
            
print_path: rts
            ldy     http.path_offset
_loop
            lda     (http.url),y
            jsr     putchar
            iny
            cpy     http.path_end
            bne     _loop
            clc
            rts

print_request: rts
            ldy     #0
_loop
            lda     io.tcp.tx_buf,y
            jsr     putchar
            iny
            cpy     io.tcp.tx_len
            bne     _loop
_out
            rts            
                        
print_remaining
            phx
            ldx     #block_size
            jsr     print_number
            plx
            rts
            

            .send
            .endn
