; WGET for the Foenix F256.
; Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

*           = $8000-9
            .byte       'z'
            .dword      $8000
            .dword      size

payload
            .binary     "../wget.bin"
start       lda         payload+3   ; block
            sta         kernel.args.run.block_id
            jmp         kernel.RunBlock

size = * - payload

            .dword      start
            .dword      0
