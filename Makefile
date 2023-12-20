# WGET for the Foenix F256.
# Copyright 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
# SPDX-License-Identifier: GPL-3.0-only

always: wget.bin wget.pgz

clean:
	rm -f *.lst *.bin *.map *.sym  labels.txt *~ src/*~

COPT = -C -Wall -Werror -Wno-shadow --verbose-list

image:
	(cd c; make)

COMMON	= \
	Makefile \
	src/io.asm \
	src/io_tcp.asm \
	src/display.asm \
	src/dns.asm \
	src/http.asm \
	src/api.asm \

WGET	= \
	src/wget.asm \
	src/file.asm \

WEXEC	= \
	src/wexec.asm \
	src/pgz.asm \

wget.bin: $(COMMON) $(WGET)
	64tass $(COPT) $(filter %.asm, $^) -b -L $(basename $@).lst -o $@

wget.pgz: src/mkpgz.asm src/api.asm wget.bin 
	64tass $(COPT) $(filter %.asm, $^) -b -o $@

wexec.bin: $(COMMON) $(WEXEC)
	64tass $(COPT) $(filter %.asm, $^) -b -L $(basename $@).lst -o $@


