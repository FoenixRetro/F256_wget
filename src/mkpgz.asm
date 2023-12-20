            .cpu    "65c02"

*           = $8000-7
            .byte       'Z'
            .word       $8000
            .byte       0
            .word       size
            .byte       0

payload
            .binary     "../wget.bin"
start       lda         payload+3   ; block
            sta         kernel.args.run.block_id
            jmp         kernel.RunBlock

size = * - payload

            .word       start
            .byte       0
            .byte       0,0,0
