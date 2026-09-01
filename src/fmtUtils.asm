;---------------------------------------
;            Getch Wrappers            :
;---------------------------------------
doYNWait:
;This does the below but also outputs a new line to 
; indicate that input has been recieved.
    call .doWait
    pushfq
    lea rdx, crlfStr
    call printString    ;Output a new line!
    popfq
    return
.doWait:
;Input: rdx -> String to wait for Y/N on.
;Output: CF=NC -> Y(es)
;        CF=CY -> N(o)
    push rdx
    call printString
    call getch
    movzx edx, al
    mov eax, 6523h  ;Zeros upper word of lower dword
    int 21h
    pop rdx
    cmp eax, 1
    ja .doWait
    return

;--------------------------------------
;          Utility functions          :
;--------------------------------------
writeDiskStats:
;Writes the disk statistics after a format.
;-------------------------------------------------------
;<Number> bytes total disk space
;<Number> bytes used by system (if /S set and system files installed)
;<Number> bytes in bad sectors (if bad sectors. Always rounds to # of clusters)
;<Number> bytes available on disk 
;
;<Number> bytes in each allocation unit.
;<Number> allocation units available on disk. ;alloc units are clusters
;
;Volume Serial Number is <Serial-Number>
;-------------------------------------------------------
;Start start by putting a new line
    lea rdx, crlfStr
    call printString
;Start by getting free sector count from DOS. We do this to make the 
; computation of the free sector count easier after /s and if any bad clusters.
    mov eax, 3600h  ;Get free space count
    movzx edx, byte [fmtDrive]
    inc edx ;Turn into a 1 based count
    int 21h
;If we have a FAT 32 drive, add one cluster to the free count to account for
; the root directory cluster.
    cmp byte [fatType], fs_fat32
    jne .goSave
    inc ebx ;Discount the root directory from initial count!
.goSave:
;Use x64 regs instead of stack frame
    mov r8, rdx ;r8 = Total cluster count in data area
    mov r9, rbx ;r9 = Free cluster count in the data area
;Total number of bytes, ebx still has total count
    movzx eax, byte [secPerClust]
    movzx ecx, word [sectorSize]
    mul ecx     ;Get the number of bytes per cluster in eax
    mov r10, rax    ;Save this value in r10
    mul r8      ;Get in eax the number of bytes on disk
    call printDecimalDword
    lea rdx, totalBytesStr
    call printString
;System bytes
    test byte [bFlag1], bitSystem
    jz .skipSystem
    mov rcx, r9     ;Get the free cluster count
    mov rax, r8     ;Get the total cluster count
    sub eax, ecx    ;Workout the amount of space taken by system files
    mov rcx, r10    ;Get word BytesPerClust
    mul ecx         ;Get the number of bytes taken by system files
    call printDecimalDword
    lea rdx, sysBytesStr
    call printString
.skipSystem:
;Bad cluster bytes
    mov ecx, dword [dBadClust]
    test ecx, ecx
    jz .skipBad
    mov rax, r8     ;Get the total cluster count
    sub eax, ecx
    mov rcx, r10    ;Get word BytesPerClust
    mul ecx         ;Get the number of bytes taken by bad clusters
    call printDecimalDword
    lea rdx, badSectStr
    call printString
.skipBad:
;Free bytes
    mov rax, r9     ;Get free cluster count
    mov rcx, r10    ;Get word BytesPerClust
    mul ecx         ;Get the number of free bytes
    call printDecimalDword
    lea rdx, availableBytesStr
    call printString
;Bytes per cluster
    mov rax, r10    ;Get word BytesPerClust
    call printDecimalDword
    lea rdx, clustSzStr
    call printString
;Number of clusters
    mov rax, r8     ;Get the total cluster count
    call printDecimalDword
    lea rdx, totClusStr
    call printString
;Vol Serial Number
    lea rdx, volSerialNumStr
    call printString
    lea rsi, qword [dSerNum]
    lodsb
    call printHexByte
    lodsb
    call printHexByte
    mov edx, "-"
    call putch
    lodsb
    call printHexByte
    lodsb
    call printHexByte
;We are done so print a new line :)
    lea rdx, crlfStr
    call printString    ;Output a new line!
    return

printHexByte:
    lea rbx, .tbl
    push rax
    shr eax, 4  ;Move nybble down
    call .phn
    pop rax
    call .phn
    return
.phn:
;Prints hex nybble in al.
    and eax, 0Fh    ;Save lower nybble only
    xlatb
    mov edx, eax
    call putch
    return
.tbl    db "0123456789ABCDEF"

writeFmtEnd:
    lea rdx, okFormat   ;Successfully formatted!
    call printString
    return
    
writeStatusUpdate:
    push rcx
    push rdx
    mov rax, qword [secWritten]
    mov ebx, 100
    mul rbx ;Multiply number of sectors by 100
    mov rbx, qword [secToWrite]
    xor edx, edx
    div rbx ;Get percentage of written sectors in rax (formally al)
    cmp al, byte [secPercent]
    je .exit    ;If they are equal, dont bother printing again
;Here we have a new percentage! Update the message!
    mov byte [secPercent], al
    mov ecx, 3  ;Max 3 chars to print (up to 100)
    call printDecimalValLB
    lea rdx, fmtPcntMsg
    call printString
    mov dl, CR
    call putch  ;End by returning to the start of the line
.exit:
    pop rdx
    pop rcx
    return 

printDecimalDword:
    push rcx
    mov ecx, 17 ;Need to make space for dword + commas
    call printDecimalValLB
    pop rcx
    return
printDecimalValLB:
;Takes a value in rax and prints it's decimal representation with leading
; blanks and inserts commas where appropriate.
;Input: rax = Value to print
;       rcx = Buffer size to handle (usual values: 17 for max, 13 for dword)
    mov rbp, rsp
    sub rsp, rcx ;Allocate the buffer on the stack
    mov rdi, rbp
    sub rdi, rcx
    push rax
    push rcx
    push rdi
    xor eax, eax
    rep stosb   ;Initialise the buffer with a null value
    pop rdi     ;Now set the ptr to the head of the buffer
    pop rcx
    pop rax
    push rcx    ;Save this value to keep the buffer length
    call decimalise   ;If return with CF=CY, error!
    pop rcx     ;Now print the buffer
    mov rdi, rbp
    dec rdi     ;Doesn't affect CF
    jc .errPrint    ;Print a mis-aligned ? to clearly mark an error!
.skipLp:
    mov bl, byte [rdi]
    test bl, bl ;Any leading null's get replaced with a space
    jne .printLp
    mov dl, " "
    call putch
    dec rdi
    dec ecx
    cmp ecx, 1
    jne .skipLp   ;Always print 1 byte for size
.printLp:
    mov dl, byte [rdi]
    call putch
    dec rdi
    dec ecx
    jnz .printLp
.exit:
    mov rsp, rbp    ;Deallocate the buffer and exit!
    return
.errPrint:
;Print a default ? symbol if an overflow occurs.
    mov dl, "?"
    call putch
    jmp short .exit

decimalise:
;Input: rax = value to decimalise
;       rdi -> Ptr to byte buffer to store string in with commas
;       ecx = buffer length
;Output: Buffer @ rdi filled in! 
;       ecx = Number of chars in buffer.
; Warning: If the number of chars in the buffer reaches buffer length,
;   we return with CF=CY. Else, CF=NC.
    push rdi
    mov esi, ecx    
    xor ecx, ecx    ;Use cl as buffer length ctr, ch as comma ctr
    mov ebx, 0Ah    ;Divide by 10
.lp:
    cmp ch, 3       ;Are we divisible by 3?
    jne .skipSep
    cmp sil, cl
    je .exitErr     ;Before we add a comma, do we have space?
    ;mov dl, byte [ctryData + countryStruc.thouSep]
    ;mov byte [rdi], dl
    mov byte [rdi], ","
    inc rdi 
    inc cl          ;Inc number of chars
    xor ch, ch      ;Reset comma counter
.skipSep:
    cmp sil, cl
    je .exitErr     ;Before we add a digit, do we have space?
    xor edx, edx
    div rbx         ;Divide rax by 10
    add dl, "0"     
    mov byte [rdi], dl
    inc rdi
    inc cl          ;Inc number of chars
    inc ch          ;Inc to keep track of commas
    test rax, rax
    jnz .lp
;The test cleared CF if we are here
    movzx ecx, cl
.exit:
    pop rdi
    return
.exitErr:
    stc
    jmp short .exit


cleanBuffer:
;Cleans the sector buffer
    mov rdi, qword [pBuffer]
    movzx ecx, word [sectorSize]
    xor eax, eax
    rep stosb   ;Clean the Sector buffer
    return

prepPrintVals:
;Compute secToWrite and initialise secWritten and secPercent.
    xor eax, eax
    mov qword [secWritten], rax   ;Initialised for when multiple formats
    mov byte [secPercent], -1
    test byte [bFlag1], bitQuick  ;If quick set, won't process rest of disk.
    jnz .quick
    mov rax, qword [numSectors]
    mov qword [secToWrite], rax
    return
.quick:
    mov eax, dword [fatSize]
    shl rax, 1  ;Multiply this value by 2 for two FATs
    mov qword [secToWrite], rax
    cmp byte [fatType], fs_fat32
    je .fat32
;Add the sectors for the root directory and single bootsector
    mov rsi, qword [bpbPtr]
    movzx eax, word [rsi + bpb.rootEntCnt]  ;Number of 32 bit entries
    shl eax, 5  ;Get number of bytes in root dir
    movzx esi, word [rsi + bpb.bytsPerSec]
    xor edx, edx
    div esi ;Get number of whole sectors in eax. edx is remainder. 
    inc eax ;Add one for the bootsector
    add qword [secToWrite], rax ;Add whole sectors and bootsector to count
    test edx, edx   ;If no remainder (should never be a remainder), exit
    retz
    inc qword [secToWrite]  ;Add one for remainder
    return
.fat32:
;Now add dir sectors and two bootsectors and two fsinfo sectors (4)
    movzx eax, byte [secPerClust]   ;Sectors per cluster (1 cluster for dir)
    add eax, 4  ;Two BS + 2 FSINFO
    add qword [secToWrite], rax
    return

writeFATStartSig:
;Writes the first two cluster blocks with the necessary signature
;Input: rdi -> Start of the FAT sector
    push rax
    push rbx
    mov rbx, qword [bpbPtr]
    movsx eax, byte [rbx + bpb.media]   ;Get the media byte, sign extend
    cmp byte [fatType], fs_fat16
    je .fat16
    ja .fat32
;Fat 12 here
    and eax, 00FFFFFFh  ;Save only low three bytes
.fat16:
    mov dword [rdi], eax
    jmp short .exit
.fat32:
    mov dword [rdi], eax
    mov eax, -1
    mov dword [rdi + 4], eax
.exit:
    pop rbx
    pop rax
    return

getVolumeID:
;Uses the time to set a volume ID
;Output: eax = VolumeID
;Preserves rbx!
    push rbx
    mov eax, 2C00h     ;Get Time in cx:dx
    int 21h
    movzx ebx, dx
    movzx eax, cx
    shl ebx, 10h
    or eax, ebx
    pop rbx
    return

computeFAT:
;Returns if FAT12/16/32 should be used for volume parameters input.
;Output: ecx = 0 => FAT 12, ecx = 1 => FAT 16, ecx = 2 => FAT 32
;All other regs preserved
    push rax
    push rdx
    push rdi
    mov rdi, [bpbPtr]   ;Get ptr to the returned bpb
;Compute space taken by fats
    movzx eax, word [rdi + bpb.FATsz16]
    movzx ecx, byte [rdi + bpb.numFATs]
    mul ecx ;Get number of sectors occupied by all the fat copies
    add ax, word [rdi + bpb.revdSecCnt] ;Add the number of reserved sectors
    add ax, word [rdi + bpb.rootEntCnt] ;Add the root dir sectors
    push rax    ;Save the non-data space
;Get the total number of sectors on the volume in eax
    movzx eax, word [rdi + bpb.totSec16]
    mov ecx, dword [rdi + bpb.totSec32]
    test eax, eax
    cmovz eax, ecx  ;Move ecx to to eax if eax is zero
    pop rcx
    sub eax, ecx    ;Get the data space only in eax.
    movzx ecx, byte [rdi + bpb.secPerClus]
    test ecx, ecx
    jecxz .err  ;If this is zero, due to malformed field, escape. Use FAT16
    xor edx, edx
    div ecx         ;Get number of clusters in eax
;Now setup the return value in ecx
    mov ecx, 2  ;FAT 32 marker
    cmp eax, fat16MaxClustCnt
    jae .exit
    dec ecx     ;FAT 16 marker
    cmp eax, fat12MaxClustCnt
    jae .exit
    dec ecx     ;FAT 12 marker
.exit:
    pop rdi
    pop rdx
    pop rax
    return
.err:
;To prevent a divide by 0 error!
    dec ecx
    jmp short .exit

computeFATSize:
; Reads from the bpb in rdi. Applies the following algorithm
; RootDirSectors = ((BPB_RootEntCnt * 32) + (BPB_BytsPerSec – 1)) / BPB_BytsPerSec;
; TmpVal1 = DskSize – (BPB_ResvdSecCnt + RootDirSectors);
; TmpVal2 = (256 * BPB_SecPerClus) + BPB_NumFATs;
; If(FATType == FAT32)
;   TmpVal2 = TmpVal2 / 2;
; FATSz = (TMPVal1 + (TmpVal2 – 1)) / TmpVal2;
;Input:
;   rdi = Pointer to the head of the BPB we are using
;Returns: 
;   eax = Number of sectors per FAT needed. Low word only valid for FAT12/16
    push rbx
    push rcx
    push rdx
    push rdi
    
    movzx eax, word [rdi + bpb.rootEntCnt]
    shl eax, 5  ;Multiply by 32
    movzx ebx, word [rdi + bpb.bytsPerSec]
    dec ebx
    add eax, ebx
    inc ebx
    xor edx, edx
    div ebx
    mov edx, eax    ;edx = RootDirSectors

    movzx eax, word [rdi + bpb.totSec16]
    mov ebx, dword [rdi + bpb.totSec32]
    test eax, eax   ;If totSec16 is 0, move totSec32 into eax
    cmovz eax, ebx
    movzx ebx, word [rdi + bpb.revdSecCnt]
    add ebx, edx    ;Add RootDirSectors
    sub eax, ebx
    mov ecx, eax    ;ecx = TmpVal1

    movzx eax, byte [rdi + bpb.secPerClus]
    shl eax, 8  ;multiply by 256
    movzx ebx, byte [rdi + bpb.numFATs]
    add ebx, eax    ;ebx = TmpVal2

    cmp byte [fatType], fs_fat32
    jne .notFat32
    shr ebx, 1  ;Divide by 2
.notFat32: 
    mov eax, ecx    ;TmpVal1
    dec ebx
    add eax, ebx    ;TmpVal1 + (TmpVal2 - 1)
    inc ebx
    xor edx, edx
    div ebx ;Exit with eax = number of sectors needed per FAT
.exit:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    return
