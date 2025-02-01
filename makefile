#!/bin/sh

format:
	nasm format.asm -o ./bin/FORMAT.COM -f bin -l ./lst/format.lst -O0v
# Now stick the generic bootloader to the end of the file
	cat ./bin/loader.bin >> ./bin/FORMAT.COM
	cat ./bin/loader32.bin >> ./bin/FORMAT.COM

loader:
	nasm ./src/loader.asm -o ./bin/loader.bin -f bin -l ./lst/loader.lst -O0v

loader32:
	nasm ./src/loader32.asm -o ./bin/loader32.bin -f bin -l ./lst/loader32.lst -O0v

all:
	nasm format.asm -o ./bin/FORMAT.COM -f bin -l ./lst/format.lst -O0v
	nasm ./src/loader.asm -o ./bin/loader.bin -f bin -l ./lst/loader.lst -O0v
	nasm ./src/loader32.asm -o ./bin/loader32.bin -f bin -l ./lst/loader32.lst -O0v	
# Now stick the generic bootloader to the end of the file
	cat ./bin/loader.bin >> ./bin/FORMAT.COM
	cat ./bin/loader32.bin >> ./bin/FORMAT.COM