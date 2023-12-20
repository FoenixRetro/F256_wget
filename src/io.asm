; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

io          .namespace

            .section    dp
            .send
            
            .section    pages
handlers    .fill       256            
            .send

            .section    data
event       .dstruct    kernel.event.event_t
            .send


            .section    code
            
          ; TODO: cookie based timer dispatching.
init

          ; Init the handlers.
            ldx     #0
_loop
            jsr     release
            inx
            inx
            bne     _loop            

          ; Init the event buffer.
            lda     #<event
            sta     kernel.args.events.dest+0
            lda     #>event
            sta     kernel.args.events.dest+1
            
            clc
            rts

dummy
            clc
            rts

release
            lda     #<dummy
            sta     handlers+0,x
            lda     #>dummy
            sta     handlers+1,x
            rts

next_event
            bit     kernel.args.events.pending
            ;beq     _yield
    
            jsr     kernel.NextEvent
            bcs     _yield

            phx
            jsr     _dispatch
            plx
            rts
            
_dispatch
            lda     event.type
            tax
            jmp     (handlers,x)
_yield
      ; This is optional, but the kernel will need time to
      ; process IP traffic, so if we have nothing better to
      ; do, giving the kernel the rest of our time is nice.

            jsr     kernel.Yield
            bra     next_event
        
            .send
            .endn            
