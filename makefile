#!/bin/sh

format:
	nasm format.asm -o ./Binaries/FORMAT.COM -f bin -l ./Listings/format.lst -O0v
# Now stick the generic bootloader to the end of the file
	cat ./Binaries/loader.bin >> ./Binaries/FORMAT.COM
	cat ./Binaries/loader32.bin >> ./Binaries/FORMAT.COM

loader:
	nasm ./Source/loader.asm -o ./Binaries/loader.bin -f bin -l ./Listings/loader.lst -O0v

loader32:
	nasm ./Source/loader32.asm -o ./Binaries/loader32.bin -f bin -l ./Listings/loader32.lst -O0v

all:
	nasm format.asm -o ./Binaries/FORMAT.COM -f bin -l ./Listings/format.lst -O0v
	nasm ./Source/loader.asm -o ./Binaries/loader.bin -f bin -l ./Listings/loader.lst -O0v
	nasm ./Source/loader32.asm -o ./Binaries/loader32.bin -f bin -l ./Listings/loader32.lst -O0v	
# Now stick the generic bootloader to the end of the file
	cat ./Binaries/loader.bin >> ./Binaries/FORMAT.COM
	cat ./Binaries/loader32.bin >> ./Binaries/FORMAT.COM