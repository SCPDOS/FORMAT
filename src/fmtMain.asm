

;We start by checking that the version number is OK
;al has flag if the passed argument is ok
;r8 points to the PSP
;String ops all go the right way on program starup
startFormat:
    jmp short .cVersion
.vNum:          db 1
.sectorSize:    dw 200h
.cVersion:
    push rax
    mov ah, 30h
    int 21h
    cmp al, byte [.vNum] ;Version 1
    jbe .okVersion
    pop rax
    lea rdx, badVerStr
.printExit:
    call printString
    jmp exitError
.okVersion:
;Check the passed argument is ok (flag in al)
    pop rax
    cmp al, -1
    jnz .driveOk
.badDrive:
    lea rdx, badDrvLtr
    jmp short .printExit
.driveOk:
;Now fetch the drive we are working on
    mov dl, byte [r8 + psp.fcb1] ;Get the fcb 1 based drvNum
    dec dl  ;Turn it into a 0 based number
    mov byte [fmtDrive], dl
    add dl, "A"             ;Turn into a ASCII char for printing
    mov byte [cancelL], dl  ;Store for cancel string
    mov byte [fmtRemStrL], dl   ;And HDD/RemDev strings
    mov byte [fmtHddStrL], dl
; Here we now hook ^C so that if the user calls ^C we restore DOS state
; (i.e. default drive and reactivate the drive if it is deactivated)
    lea rdx, breakRoutine
    mov eax, 2523h
    int 21h
.driveSelected:
;Now we check that the associate drive is not a network, subst or join.
; If it is, fail. Else, we deactivate
    mov eax, 5200h
    int 21h ;Get in rbx a ptr to list of lists
    add rbx, 2Ah    ;Point rbx to cdsHeadPtr
    mov rsi, qword [rbx]    ;Get the ptr to the CDS array
    movzx ecx, byte [fmtDrive]
    jecxz .atCurrentCDS
.walkCDSArray:
    add rsi, cds_size
    dec ecx
    jnz .walkCDSArray
.atCurrentCDS: 
;Cannot format a Redir drive for now (Will use the net redirector for this)
    test word [rsi + cds.wFlags], cdsRedirDrive
    jnz badNetExit
;Cannot format a subst drive
    test word [rsi + cds.wFlags], cdsSubstDrive
    jnz badSubstExit
    mov qword [cdsPtr], rsi ;Save a ptr to the current CDS
;Now attempt to ascertain if removable or not.
    movzx ebx, byte [fmtDrive]    ;0 based number
    inc ebx  ;Turn it into a 1 based number
    mov eax, 4408h  ;IOCTL, Get if removable or not. Should never fail
    int 21h
    jc badIOCTLExit.alt ;Don't print format failed!
    test al, al
    jz .gotRemDev
    or byte [media], 8      ;Turn to 0F8h
    mov byte [remDev], -1   ;Indicate Fixed drive
;Print the Hard Drive Partition warning string.
    lea rdx, fmtHddStr
    call doYNWait
    pushfq
    lea rdx, crlfStr
    call printString
    popfq
    jnc exitNoFormatFixed   ;CF=NC means don't proceed
    jmp short .getDrvParams
.gotRemDev:
;Print the rem dev warning string
    lea rdx, fmtRemStr
    call printString
    call getch  ;Any char will proceed us
.getDrvParams:
;Print CRLF to signal remdev inserted/fixed disk warning accepted
    lea rdx, crlfStr
    call printString
;Now request IOCTL to give medium parameters
;Get from BPB as this should be synced with disk (this is to handle ufmtd media).
;Hence, don't hit the disk (also this protects if the user has overwritten 
; sector 0 somehow)
    mov eax, specFuncBPB
    call getBpb
    jc badIOCTLExit
;Setup pointer to the BPB we will be using to report format
    lea rdi, qword [rdx + chsParamsBlock.deviceBPB] ;Point to BPB
    mov qword [bpbPointer], rdi ;Store this as the BPB buffer pointer
;Now setup internal vars
;Ensure that we always set the number of FATs to 2
    mov byte [rdi + bpb.numFATs], 2
    movzx ebx, word [rdi + bpb.bytsPerSec]
;TEMP: ONLY ALLOW FORMATTING ON "NORMAL" (512 byte sectors) MEDIA FOR NOW
    cmp word [startFormat.sectorSize], bx 
    jne badSecSizeExit
;TEMP: END OF TEMP
    mov word [sectorSize], bx
    mov eax, dword [rdi + bpb.hiddSec]
    mov dword [hiddSector], eax
    movzx eax, word [rdi + bpb.totSec16]
    mov ecx, dword [rdi + bpb.totSec32]
    test eax, eax   ;If totSec16 is 0, use totSec32
    cmovz eax, ecx
    mov qword [numSectors], rax
;Allocate a sector sized memory block for IO. bx has sector size in bytes
    shr ebx, 4  ;Divide by 16 to get number of paragraphs
    mov eax, 4800h  ;Allocate
    int 21h
    jc badExitGen
    mov qword [bufferArea], rax ;Use this space as IO buffer
    call cleanBuffer
;Now we select the FAT based on the size of the volume
    movzx ebx, word [sectorSize]
    mov rax, qword [numSectors] ;Get the number of sectors in rax
    mul rbx         ;Multiply to get number of bytes on volume in rax
    mov rbx, 1FFFFFFFE00h ;If our volume is above 2Tb in size, abort
    cmp rax, rbx
    jnb badVolExit
    xor ebx, ebx
    mov byte [fatType], 0   ;Start by saying it must be FAT12
    mov ecx, 4  ;4 entries in the fat16table without the first entry
    lea rsi, fat16ClusterTable
    cmp eax, dword [rsi]
    jbe .medFound   ;Here we need to build a custom BPB for this device. 
    inc byte [fatType]  ;Make now FAT 16
    add rsi, 5  ;Goto next entry    
.fat16Lp:
    mov ebx, dword [rsi]    ;Clears upper 32 bytes of ebx
    cmp rax, rbx
    jbe .medFound
    add rsi, 5
    dec ecx
    jnz .fat16Lp
    inc byte [fatType]
    mov ecx, 4
.fat32Lp:
    cmp rax, qword [rsi]
    jbe .medFound
    add rsi, 9
    dec ecx
    jnz .fat32Lp
    jmp badVolExit
.medFound:
;Called with rsi pointing to the table entry
    mov al, byte [rsi + 4]  ;Get the sector per cluster value in al
    mov byte [secPerClust], al
;Now we select the bootsector in the payload section
    lea rbx, bootloader         ;Point to the FAT12/16 generic one
    mov qword [loaderPtr], rbx  ;And store it. If FAT32, we will adjust below
    cmp byte [fatType], 2
    je .fat32
    lea rsi, genericBPB12
    lea rdi, genericBPB16
    cmp byte [fatType], 1
;Now we copy the correct generic bpb into the CHS IOCTL param block
    cmove rsi, rdi  ;Use FAT16 BPB if FAT16 volume
    mov ecx, bpb_size
    mov byte [bpbSize], cl
    mov rdi, qword [bpbPointer]
    push rdi    ;Save ptr to the bpb in the param block
    rep movsb   ;Copy the correct generic BPB into the bpb buffer
    pop rdi     ;Point rdi back to the bpb field in the param block
    mov al, byte [media]
    mov byte [rdi + bpb.media], al
    mov eax, dword [hiddSector]
    mov dword [rdi + bpb.hiddSec], eax
    mov ax, word [sectorSize]
    mov word [rdi + bpb.bytsPerSec], ax
    mov al, byte [secPerClust]
    mov byte [rdi + bpb.secPerClus], al
    mov rax, qword [numSectors]
    test eax, 0FFFFh
    jnb .largeSectors
    mov word [rdi + bpb.totSec16], ax
    jmp short .sectorsOK
.largeSectors:
    mov word [rdi + bpb.totSec16], 0
    mov dword [rdi + bpb.totSec32], eax
.sectorsOK:
    call computeFATSize
    mov word [rdi + bpb.FATsz16], ax
    movzx eax, ax
    mov dword [fatSize], eax
    jmp short .bpbReady
.fat32:
    add qword [loaderPtr], 200h
;Copy the generic FAT32 bpb into the bpb buffer and modify it
    mov ecx, bpb32_size
    mov byte [bpbSize], cl
    lea rsi, genericBPB32
    mov rdi, qword [bpbPointer]
    push rdi    ;Save ptr to the bpb in the param block
    rep movsb   ;Copy the correct generic BPB into the bpb buffer
    pop rdi     ;Point rdi back to the bpb field in the param block
    mov al, byte [media]
    mov byte [rdi + bpb32.media], al
    mov eax, dword [hiddSector]
    mov dword [rdi + bpb.hiddSec], eax
    mov ax, word [sectorSize]
    mov word [rdi + bpb32.bytsPerSec], ax
    mov al, byte [secPerClust]
    mov byte [rdi + bpb32.secPerClus], al
    mov eax, dword [numSectors]
;    mov word [rdi + bpb32.totSec16], 0 ;Already 0 in the copied version
    mov dword [rdi + bpb32.totSec32], eax
    call computeFATSize
    mov dword [rdi + bpb32.FATsz32], eax
    mov dword [fatSize], eax
    mov word [rdi + bpb32.extFlags], 0  ;FAT mirroring active
    ;Here we need to assign cluster 2 to be root dir. Later we
    ; check to see if we can actually use cluster 2. If yes, 
    ; we allocate it on the FAT. If not, we reassign the root 
    ; dir location
    mov word [rdi + bpb32.secPerTrk], 03Fh
    mov word [rdi + bpb32.numHeads],  0FFh
    mov dword [rdi + bpb32.RootClus], 2
.bpbReady:
;Now setup bootsector for writing
    call prepPrintVals
    mov rbx, qword [bufferArea]    
    mov rdi, rbx    ;Point rdi to the buffer
;Now copy the default bootsector into the buffer
    mov rsi, qword [loaderPtr]
    movzx ecx, word [sectorSize]
    rep movsb   ;Copy the bootsector into the sector buffer
;Now copy the accurate BPB into the bootsector
    lea rdi, qword [rbx + 11]    ;Point rdi to the BPB in the sector
    mov rsi, qword [bpbPointer]
    movzx ecx, byte [bpbSize]   ;Now copy the bpb
    rep movsb   ;moves rdi to start of extended BPB area of the bootsector
;Finally, now that the bootsector is ready, setup the extended BPB fields.
    mov al, byte [remDev]
    and al, 80h ;Save only bit 7
    mov byte [rdi + extBs.drvNum], al
    call getVolumeID    ;Gets a fresh ID in eax
    mov dword [rdi + extBs.volId], eax
;Now make the bootsector not bootable!
    mov rbx, qword [bufferArea] ;rbx = Memory Buffer address to read from
    mov byte [rbx + 509], 0 ;Make the disk not bootable
    mov word [rbx + 510], 0AA55h
;Now sync the new BPB with the driver
    mov eax, specFuncBPB ;Lock the BPB for the update
    call syncBpb
    jc badIOCTLExit
proceedFormat:
    lea rdx, fmtMsg     ;Now we are about to write, print this message
    call printString
    call dosCrit1Enter
    call setDriveAccess ;Enable drive access now!

    mov ecx, 1      ;ecx = Number of sectors to write
    xor edx, edx    ;rdx = Start LBA to write to
    call writeSector
    jc badBtSctrExit
    cmp byte [fatType], 2  ;If not 2 (FAT32), skip backup bootsector
    jne writeFat
;Now we write the backup BPB too at sector 6
    mov ecx, 1  ;1 Sector to write
    mov edx, 6  ;At sector 6
    call writeSector
    jnc writeFat
;If something goes wrong writing the backup, set the backup bootsector 
; to sector 0 as the standard allows this and proceed.
    mov rdx, qword [bpbPointer]  ;Get the loader addr
    mov word [rbx + bpb32.BkBootSec], 0    ;Set the backup sector to 0
    mov ecx, 1      ;ecx = Number of sectors to write
    xor edx, edx    ;rdx = Start LBA to write to
    call writeSector
    jc badBtSctrExit   ;If this fails, it means bs is being dodgy. Fail!
writeFat:
    mov eax, ~specFuncBPB    ;Unlock the BPB
    call syncBpb    ;Finish by syncing the BPB again
    jc badIOCTLExit
;Now we create the FAT sectors.
;We write both copies one sector at a time interleaving them.
    mov esi, dword [fatSize]    ;Get the number of sectors to write, as counter
    call cleanBuffer
    mov rdi, qword [bufferArea] ;Point rdi to the head of buffer area
    call writeFATStartSig   ;Write the first two clusters in the map
    mov ecx, 1  ;ecx = Number of sectors to write
    mov rdi, qword [bpbPointer] ;Get the ptr to the BPB
    movzx edx, word [rdi + bpb.revdSecCnt]  ;Get the first sector past reserved
    push rdx
    push rsi
    call writeSector
    pop rsi
    pop rdx
    jc badFATExit
    mov eax, dword [fatSize]
    add edx, eax    ;Go to second fat copy
    mov ecx, 1
    push rax
    push rdx
    push rsi
    call writeSector
    pop rsi
    pop rdx
    pop rax
    jc badFATExit
    mov rdi, qword [bufferArea]
    mov qword [rdi], 0  ;Overwrite the FAT reserved cluster markers
    mov dword [rdi + 8], 0  ;Overwrite potential additional FAT32 data
    dec esi ;Decrement the number of fat sectors left to count
fatFillLoop:
    sub edx, eax    ;Come back to the first FAT copy
    inc edx ;Goto next sector
    mov ecx, 1
    push rdx
    push rsi
    call writeSector
    pop rsi
    pop rdx
    jc badFATExit
    mov eax, dword [fatSize]
    add edx, eax    ;Go to second fat copy
    mov ecx, 1
    push rax
    push rdx
    push rsi
    call writeSector
    pop rsi
    pop rdx
    pop rax
    jc badFATExit
    dec esi
    jnz fatFillLoop
    ;Fall through once done with FAT
rootDirectory:
    ;FAT12 and 16 are simple, FAT32 is a bit more complex
    cmp byte [fatType], 2
    je .fat32
    ;Here we compute the number of Root Dir sectors and sanitise them
    ;rdx should point to that sector now (since it works on FAT copy 2 last)
    mov rbx, qword [bpbPointer]
    movzx esi, word [rbx + bpb.rootEntCnt]  ;Get the number of 32 byte entries
    shl esi, 5  ;Convert into the number of bytes in root directory
    movzx eax, word [sectorSize]    ;Get the sector size
    xchg esi, eax
    push rdx
    xor edx, edx
    div esi ;Divide to get number of sectors in eax, preserve edx
    pop rdx ;Save edx
    mov esi, eax    ;Number of sectors in esi
    mov ecx, 1  ;Write one sector
.fatLoop:
    inc edx ;Go to next sector now
    push rcx
    push rdx
    push rsi
    call writeSector
    pop rsi
    pop rdx
    pop rcx
    jc badDirExit
    dec esi
    jnz .fatLoop
    jmp exitFormat
.fat32:
;Now we need to allocate a cluster to the root directory. We need to 
; then sanitise the cluster completely.
;Step 1) Get back the FAT sector.
;Step 2) Allocate Cluster 2
;Step 3) Write back.
;Step 4) Write back copy.
;Step 5) Loop through sectors of the cluster nulling the sector out
    mov ecx, 1
    movzx edx, word [genericBPB32 + bpb32.revdSecCnt]
    push rcx
    push rdx
    call readSector
    pop rdx
    pop rcx
    mov rbx, qword [bufferArea]
    mov dword [rbx + 8], -1    ;Allocate this cluster
    push rcx
    push rdx
    call writeSector
    pop rdx
    pop rcx
    jc badDirExit
    add edx, dword [genericBPB32 + bpb32.FATsz32]   ;Go to backup FAT sector
    push rdx
    call writeSector
    pop rdx
    jc badDirExit
    add edx, dword [genericBPB32 + bpb32.FATsz32]   ;Go to first data sector
    call cleanBuffer    ;Clean the buffer for writeback
    movzx esi, byte [genericBPB32 + bpb32.secPerClus]
    mov ecx, 1
.fat32RootClean:
    push rcx
    push rdx
    push rsi
    call writeSector
    pop rsi
    pop rdx
    pop rcx
    jc badDirExit
    inc edx ;Next consecutive sector
    dec esi ;Decrement count
    jnz .fat32RootClean
;Before we write the FSinfo sector, we compute the free cluster count
    movzx ecx, byte [genericBPB32 + bpb32.numFATs]
    mov eax, dword [genericBPB32 + bpb32.FATsz32]
    mul ecx ;Get the number of sectors in the FATs
    movzx ecx, word [genericBPB32 + bpb32.revdSecCnt]    
    add eax, ecx    ;Reserved + total fat sectors in eax
    mov ecx, dword [genericBPB32 + bpb32.totSec32]
    sub ecx, eax    ;Get the number of sectors in the data area
    mov eax, ecx    ;And save it into eax
    movzx ecx, byte [genericBPB32 + bpb32.secPerClus]   
    xor edx, edx    ;Get sector per cluster cnt
    div ecx         ;Divide data area sectors/sectors per cluster
    ;eax has clusters in the data area
    dec eax         ;Drop one cluster for the allocated root dir cluster
    mov edx, eax    ;Save this value in edx
;Now we are done with the common bit, last thing for FAT32, create the
; FSInfo (with no useful info, for now as DOS will not sync this)
    call cleanBuffer
    mov dword [rbx], 41615252h  ;Initial signature
    mov dword [rbx + 484], 61417272h    ;Intermediate signature
    mov dword [rbx + 488], edx ;Free cluster count
    mov dword [rbx + 492], 3   ;First free cluster, after root dir!
    mov dword [rbx + 508], 0AA550000h
    mov ecx, 1
    mov edx, 1
    push rcx
    call writeSector
    pop rcx
    jc badFSINFOExit
    mov edx, 7
    call writeSector
    jc badFSINFOExit
exitFormat:
    call dosCrit1Exit
    lea rdx, okFormat   ;Successfully formatted!
    call printString
    test byte [remDev], -1  ;Was this drive fixed? Set if so.
    jnz exitOk
;If we formatted on a remdev, ask if we wanna go again?
    lea rdx, againStr
    call doYNWait
    pushfq
    lea rdx, crlfStr
    call printString    ;Output a new line!
    popfq
    jnc exitOk  ;If not, we are done!
    lea rdx, crlfStr
    call printString    ;Output a new line!
    jmp startFormat.gotRemDev ;And prompt user to insert new media in drive :)

;--------------------------------------
;          Utility functions          :
;--------------------------------------
writeStatusUpdate:
    push rcx
    push rdx
    mov rax, qword [secWritten]
    mov ebx, 100
    mul rax ;Multiply number of sectors by 100
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
    mov rdi, qword [bufferArea]
    movzx ecx, word [sectorSize]
    xor eax, eax
    rep stosb   ;Clean the Sector buffer
    return

prepPrintVals:
;Compute secToWrite and initialise secWritten and secPercent.
    mov qword [secWritten], 0
    mov byte [secPercent], -1
    test byte [quickByte], -1
    jnz .quick
    mov rax, qword [numSectors]
    mov qword [secToWrite], rax
    return
.quick:
    mov eax, dword [fatSize]
    shl rax, 1  ;Multiply this value by 2 for two FATs
    mov qword [secToWrite], rax
    cmp byte [fatType], 2
    je .fat32
    mov rsi, qword [bpbPointer]
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
    mov rbx, qword [bpbPointer]
    movsx eax, byte [rbx + bpb.media]   ;Get the media byte, sign extend
    cmp byte [fatType], 1
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
    mov eax, 2C00h     ;Get Time in cx:dx
    int 21h
    movzx ebx, dx
    movzx eax, cx
    shl ebx, 10h
    or eax, ebx
    return

computeFATSize:
; ;Works on the genericBPB in memory. Applies the following algorithm
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

    cmp byte [fatType], 2
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

;----------------------------------------
;          Error Exit wrappers          :
;----------------------------------------
;If we need "Format failed" printed, print before jumping here
badBtSctrExit:
    call restoreBpb     ;Handle BPB driver state restore
    lea rdx, badFmtFail
    call printString
    lea rdx, badBtStrWr 
    jmp badExitCmn
badFATExit:
    lea rdx, badFmtFail
    call printString
    lea rdx, badFATWr
    jmp short badExitCmn
badDirExit:
    lea rdx, badFmtFail
    call printString
    lea rdx, badDirWr
    jmp short badExitCmn
badFSINFOExit:
    lea rdx, badFmtFail
    call printString
    lea rdx, badFSInfoWr
    jmp short badExitCmn
badIOCTLExit:
    lea rdx, badFmtFail
    call printString
.alt:
    lea rdx, badIOCTL
    jmp short badExitCmn
badVolExit:
    lea rdx, badVolBig
    jmp short badExitCmn
badSecSizeExit:
    lea rdx, badSecSize
    jmp short badExitCmn
badNetExit:
    lea rdx, badNetDrv
    jmp short badExitCmn
badSubstExit:
    lea rdx, badSubsDrv
    jmp short badExitCmn
badExitGen:
    lea rdx, badGeneric
badExitCmn:
;Jumped to with rdx = Error message or 0 if no message
    call dosCrit1Exit   ;Just returns if not in a critical section
    test rdx, rdx
    jz .noPrint
    call printString
.noPrint:
    jmp exitError

;---------------------------------------
;            Getch Wrappers            :
;---------------------------------------

doYNWait:
;Input: rdx -> String to wait for Y/N on.
;Output: CF=NC -> N
;        CF=CY -> Y
    push rdx
    call printString
    call getch
    cmp al, "y"
    je .yes
    cmp al, "Y"
    je .yes
    cmp al, "n"
    je .no
    cmp al, "N"
    je .no
    pop rdx
    jmp short breakRoutine
.yes:
    stc
.no:
    pop rdx
    return

;---------------------------------------
;            CTRL+C handler            :
;---------------------------------------

breakRoutine:
;This subroutine is called by ^C
;Prompts the user for what they want to do
    lea rdx, cancel
    call doYNWait   ;If returns with CF=CY, exit! Else just redo operation!
    jnc .breakReturnNoExit
    call dosCrit1Exit   ;Exit the critical section since we are quitting
    mov eax, 4C03h      ;Tell DOS to terminate with error level 3
;Let DOS reclaim memory and handles allocated to us
.breakReturnNoExit:
    push rax
    push rdx
    lea rdx, crlfStr
    call printString
    pop rdx
    pop rax
    iretq   ;Redo the operation

;---------------------------------------
;             DOS wrappers             :
;---------------------------------------
restoreBpb:
;Gets the BPB from the bootsector again to restore the driver state.
    mov eax, specFuncBPB    ;Get the backup bpb (which is old prev bpb)
    call getBpb
    jnc .gotBpb
.bad:
;If we cant even get the BS anymore, lock drive (if fixed).
    test byte [remDev], -1
    retz
    call resetDriveAccess
    return
.gotBpb:
;Now sync it back
    mov eax, specFuncBPB
    call syncBpb
    mov eax, ~specFuncBPB
    call syncBpb
    return

getBpb:
;Gets the BPB from the bootsector into the buffer
;Input: = al[0] = Set if we return backup bpb. Clear if get from disk.
    mov ecx, 0860h         ;Disk drive type IOCTL, get FAT parameters
    jmp short syncBpb.cmn
syncBpb:
;Input: al[0] = Set if to lock bpb. Clear if to unlock bpb.
;Output: Returns if ok. Doesn't return if something went wrong.
;       Handles errors internally and exits.
    mov ecx, 0840h          ;Disk drive type IOCTL, set FAT parameters
    or eax, specFuncSec     ;We only format media to all sectors equal size
.cmn:
    lea rdx, ioParams       ;Point to parameter block
    mov byte [rdx + chsParamsBlock.bSpecFuncs], al
    movzx ebx, byte [fmtDrive]
    inc ebx
    mov eax, 440Dh      ;Generic IOCTL 
    int 21h
    return

getch:
;Output: al = Char
    mov eax, 0100h ;Get a char
    int 21h
    return
putch:
;Input: dl = Char
    mov eax, 0200h
    int 21h
    return
printString:
;Input: rdx -> $ terminated string to print
    mov eax, 0900h
    int 21h
    return

checkBreak:
;Checks if control C has been struck and triggers Int 23h.
;21h/0Bh does a non-blocking check of the keyboard buffer status.
;If there is a Ctrl+C waiting in buffer, it triggers Int 23h.
;If the user then doesn't want to exit the program, it reenters 
; the call to check the keyboard status which will just return 
; if the buffer is full or empty.
;If no Ctrl+C waiting in the buffer, it just return the keyboard status.
    mov eax, 0B00h
    int 21h
    return

exitOk:
    mov eax, 4C00h
    int 21h
exitError:
    mov eax, 4C04h
    int 21h
exitNoFormatFixed:
    mov eax, 4C05h
    int 21h

readSector:
;Input:
;ecx = Number of sectors to read
;rdx = Start LBA to read from
    call checkBreak
    mov al, byte [fmtDrive]     ; Always read from fmtDrive
    mov rbx, qword [bufferArea] ; Memory Buffer address to read from
    int 25h
    pop rax ;Pop old flags into rax
    return
writeSector:
;Input:
;ecx = Number of sectors to write
;rdx = Start LBA to write to
    call checkBreak
    call writeStatusUpdate      ; Update the percentage done message!
    mov al, byte [fmtDrive]     ; Always write to fmtDrive
    mov rbx, qword [bufferArea] ; Memory Buffer address to read from
    inc qword [secWritten]  ;Always inc even if failed. Bad sectors get marked.
    int 26h
    pop rax ;Pop old flags into rax
    return

setDriveAccess:
;For now, I will simply force drive access on!
    mov byte [accFlgPkt + accFlgBlk.bAccMode], -1
    jmp short resetDriveAccess.cmn
resetDriveAccess:
    mov byte [accFlgPkt + accFlgBlk.bAccMode], 0
.cmn:
    lea rdx, accFlgPkt
    mov ecx, 0847h  ;Set Access flag on disk drive
    movzx ebx, byte [fmtDrive]
    inc ebx ;Turn into a 1 based drive number
    mov eax, 440Dh  ;Generic IOCTL
    int 21h
    return

;Do not put the whole format through a critical section, that is insane!
;Use a DOS networking extension to obtain a handle to the drive.
dosCrit1Enter:
    mov byte [inCrit], -1   ;Entering a DOS level 1 critical section
    ;push rax 
    ;mov eax, 8001h
    ;int 2ah
    ;pop rax
    return
dosCrit1Exit:
    test byte [inCrit], -1  ;If we are not in a critical section, just return
    retz
    ;push rax 
    ;mov eax, 8101h          
    ;int 2ah
    ;pop rax
    mov byte [inCrit], 0    ;Indicate we have exited the critical section
    return