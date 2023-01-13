format:
	nasm format.asm -o ./Binaries/FORMAT.COM -f bin -l ./Listings/format.lst -O0v
# Now stick the generic bootloader to the end of the file
	cat ./Binaries/loader.bin >> ./Binaries/FORMAT.COM
	cat ./Binaries/loader32.bin >> ./Binaries/FORMAT.COM
