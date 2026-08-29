;We start by checking that the version number is OK
;al has flag if the passed argument is ok
;r8 points to the PSP
;String ops all go the right way on program starup
startFormat:
    jmp short .cVersion
.vNum:          db 1
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
    mov qword [cdsPtr], rsi ;Save a ptr to the current CDS
;Must be a valid drive do be formatted
    test word [rsi + cds.wFlags], cdsValidDrive
    jz startFormat.badDrive
;Cannot format a Redir drive for now (Will use the net redirector for this)
    test word [rsi + cds.wFlags], cdsRedirDrive | cdsRdirLocDrive
    jnz badNetExit
;Cannot format a subst drive
    test word [rsi + cds.wFlags], cdsSubstDrive
    jnz badSubstExit
;Cannot format a joined drive
    test word [rsi + cds.wFlags], badJoinDrv
    jnz badJoinExit
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
    jc exitNoFormatFixed   ;CF=CY means no, don't proceed.
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
    mov qword [bpbPtr], rdi ;Store this as the BPB buffer pointer

;
;Now setup internal vars. Trust the returned BPB even for FAT12 floppies,
; as even if the media doesn't have a BPB on it, the driver will return
; one to us. The format operation will then lay a fresh BPB on the media too.
;This means we convert old floppies to the new, better format.
;

;Ensure that we always set the number of FATs to 2
    mov byte [rdi + bpb.numFATs], 2
    movzx ebx, word [rdi + bpb.bytsPerSec]
;TEMP: ONLY ALLOW FORMATTING ON "NORMAL" (512 byte sectors) MEDIA FOR NOW
    cmp word [sectorSize], bx 
    jne badSecSizeExit
    ;mov word [sectorSize], bx
;TEMP: END OF TEMP
    movzx eax, byte [rdi + bpb.secPerClus]  ;Store the reported secPerClus val
    mov byte [secPerClust], al
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
    mov qword [pBuffer], rax ;Use this space as IO buffer
    call cleanBuffer
;Now we select the FAT based on the size of the volume.
;If a hard drive, it is automatically a FAT 16 or 32 media.
fatSelect:
    mov byte [fatType], fs_fat12   ;Init fatType to be FAT 12
    test byte [remDev], -1
    jnz .notFat12
;If removable, check media byte.
; If media byte known (F9h-FFh), we trust the driver data as these
; come from tables we know to be FAT12 OK.
; If media byte F0h, we again treat this as a marker to trust whatever 
; the driver gave us but we check FAT12 compliance.
;   If F0h volume compliant, we setup for FAT12.
; Else, use FAT16.
    cmp byte [media], 0F9h
    ja .medOk
    cmp byte [media], 0F0h
    jne .notFat12
;Now we check if the number of clusters on this volume is for FAT12. If so,
; we are ok. Else, we do FAT 16.
    call computeFAT ;If returns ecx = 0, we use FAT12!
    test ecx, ecx
    jnz .notFat12
.medOk:
;Here we have a valid FAT 12 bpb given by the driver.
    lea rsi, qword [secPerClust - 4]    ;Point rsi four bytes before this
    jmp short .medFound
.notFat12:
;Here for FAT 16 or 32 entries.
    inc byte [fatType]  ;Start by noting we are at least FAT 16
    movzx ebx, word [sectorSize]
    mov rax, qword [numSectors] ;Get the number of sectors in rax
    mul rbx         ;Multiply to get number of bytes on volume in rax
    mov rbx, 1FFFFFFFE00h ;If our volume is above 2Tb in size, abort
    cmp rax, rbx
    jnb badVolExit
    xor ebx, ebx
    mov ecx, 4  ;4 entries in the fat16table without the first entry
    lea rsi, fat16ClusterTable
    cmp eax, dword [rsi]
    jbe .medFound   ;Here we need to build a custom BPB for this device. 
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
;Now we select the bootsector in the payload section
;rsi points to the table entry
    lea rbx, bootloader         ;Point to the FAT12/16 generic one
    mov qword [pBtLdr], rbx  ;And store it. If FAT32, we will adjust below
    cmp byte [fatType], fs_fat32
    je .fat32
    mov al, byte [rsi + 4]  ;Get the sector per cluster value in al
    mov byte [secPerClust], al
    lea rsi, genericBPB12
    lea rdi, genericBPB16
    cmp byte [fatType], fs_fat16
;Now we copy the correct generic bpb into the CHS IOCTL param block
    cmove rsi, rdi  ;Use FAT16 BPB if FAT16 volume
    mov ecx, bpb_size
    mov byte [bpbSize], cl
    mov rdi, qword [bpbPtr]
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
    cmp eax, 0FFFFh
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
    jmp .bpbReady
.fat32:
    mov al, byte [rsi + 8]  ;Get the sector per cluster value in al
    mov byte [secPerClust], al
    add qword [pBtLdr], 200h ;Go past the first bootsector in memory
;Copy the generic FAT32 bpb into the bpb buffer and modify it
    mov ecx, bpb32_size
    mov byte [bpbSize], cl
    lea rsi, genericBPB32
    mov rdi, qword [bpbPtr]
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
;Now setup bootsector for writing.
;Entered with rsi -> extBS to write to
    push rsi    ;Save the ptr to the extBS to use on stack
    call prepPrintVals
    mov rbx, qword [pBuffer]    
    mov rdi, rbx    ;Point rdi to the buffer
;Now copy the default bootsector into the buffer
    mov rsi, qword [pBtLdr]
    movzx ecx, word [sectorSize]
    rep movsb   ;Copy the bootsector into the sector buffer
;Now copy the accurate BPB into the bootsector
    lea rdi, qword [rbx + 11]    ;Point rdi to the BPB in the sector
    mov rsi, qword [bpbPtr]
    movzx ecx, byte [bpbSize]   ;Now copy the bpb
    rep movsb
;Now setup the extended BPB fields.
    pop rsi ;Get back the extBS ptr to use
    movzx eax, byte [remDev]
    and eax, 80h ;Save only bit 7
    mov word [rsi + extBs.drvNum], ax   ;Clear the reserved field too
    call getVolumeID    ;Gets a fresh ID in eax (preserve rbx->bootsector)
    mov dword [rsi + extBs.volId], eax
    mov dword [dSerNum], eax  ;Save the serial number
;Now copy the extended BPB fields too!
    mov ecx, extBs_size
    rep movsb
;Finally, make the bootsector not bootable!
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
    cmp byte [fatType], fs_fat32  ;If not FAT32, skip backup bootsector
    jne writeFat
;------------------
;Do FAT32 here
;------------------
;Now we write the backup BPB too at sector 6
    mov ecx, 1  ;1 Sector to write
    mov edx, 6  ;At sector 6
    call writeSector
    jnc writeFat
;If something goes wrong writing the backup, set the backup bootsector 
; to sector 0 as the standard allows this and proceed.
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
    mov rdi, qword [pBuffer] ;Point rdi to the head of buffer area
    call writeFATStartSig   ;Write the first two clusters in the map
    mov ecx, 1  ;ecx = Number of sectors to write
    mov rdi, qword [bpbPtr] ;Get the ptr to the BPB
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
    mov rdi, qword [pBuffer]
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
    cmp byte [fatType], fs_fat32
    je .fat32
    ;Here we compute the number of Root Dir sectors and sanitise them
    ;rdx should point to that sector now (since it works on FAT copy 2 last)
    mov rbx, qword [bpbPtr]
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
    call writeFmtEnd    ;Write the disk formatted message
    jmp exitFormat
.fat32:
;------------------
;Do FAT32 here
;------------------
;Now we need to allocate a cluster to the root directory. We need to 
; then sanitise the cluster completely.
;Step 1) Get back the FAT sector.
;Step 2) Allocate Cluster 2
;Step 3) Write back, without updating the percentage.
;Step 4) Write back copy.
;Step 5) Loop through sectors of the cluster nulling the sector out
;Step 6) Decrement the Total Cluster Count as root now perma-allocated.
    mov rcx, qword [secToWrite]
    mov rcx, qword [secWritten]
    mov ecx, 1
    mov rdi, qword [bpbPtr]
    movzx edx, word [rdi + bpb32.revdSecCnt]
    push rcx
    push rdx
    call readSector
    pop rdx
    pop rcx
    mov rbx, qword [pBuffer]
    mov dword [rbx + 8], -1     ;Allocate this cluster
    push rcx
    push rdx
    call writeSectorBreak   ;Write without updating the count
    pop rdx
    pop rcx
    jc badDirExit
    add edx, dword [rdi + bpb32.FATsz32]   ;Go to backup FAT sector
    push rdx
    call writeSectorBreak
    pop rdx
    jc badDirExit
    add edx, dword [rdi + bpb32.FATsz32]   ;Go to first data sector
    push rdi
    call cleanBuffer    ;Clean the buffer for writeback
    pop rdi
    movzx esi, byte [rdi + bpb32.secPerClus]
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
;Now we are done with the common bit, last thing for FAT32, create the
; FSInfo (with no useful info, for now as DOS will sync this)
    call cleanBuffer
    mov rbx, qword [pBuffer]
    mov dword [rbx], 41615252h          ;Initial signature
    mov dword [rbx + 484], 61417272h    ;Intermediate signature
    mov dword [rbx + 488], -1 ;Force a count
    mov dword [rbx + 492], 3  ;First free cluster, after root dir!
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
    call writeFmtEnd    ;Write the disk formatted message
;Now we sync DOS's free cluster count. Warn the user of the possible delay.
    lea rdx, freeSpcStr
    call printString
    mov eax, 3600h  ;Get free space count
    movzx edx, byte [fmtDrive]
    inc edx ;Turn into a 1 based count
    int 21h
    lea rdx, completeStr    ;Indicate computation done!
    call printString
exitFormat:
    call dosCrit1Exit
    call writeDiskStats     ;Write the stats on the volume we just formatted
    test byte [remDev], -1  ;Was this drive fixed? Set if so.
    jnz exitOk
;If we formatted on a remdev, ask if we wanna go again?
    lea rdx, againStr
    call doYNWait
    jc exitOk  ;If CF=CY, we said no and we are done!
    lea rdx, crlfStr
    call printString    ;Output a new line!
    jmp startFormat.gotRemDev ;And prompt user to insert new media in drive :)

;---------------------------------------
;            CTRL+C handler            :
;---------------------------------------

breakRoutine:
;This subroutine is called by ^C
;Prompts the user for what they want to do.
;Preserve registers across call.
;
;We always return IRETQ which means we always execute the 
; function code that we return to DOS in eax. Unless we wish
; to terminate, we just re-attempt the function that was 
; ^C-ed.
;
    push rdx
    push rax
    lea rdx, cancel
    call doYNWait       ;If ret CF=NC, we said yes so exit! Else just redo op!
    jc .noAbort
    call dosCrit1Exit   ;Exit the critical section since we are quitting
    pop rax
    mov eax, 4C03h      ;Tell DOS to terminate with error level 3
    push rax
;Let DOS reclaim memory and handles allocated to us
.noAbort:
    mov dl, LF
    call putch
    pop rax
    pop rdx
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

readSector:
;Input:
;ecx = Number of sectors to read
;rdx = Start LBA to read from
    call checkBreak
    mov al, byte [fmtDrive]     ; Always read from fmtDrive
    mov rbx, qword [pBuffer] ; Memory Buffer address to read from
    int 25h
    pop rax ;Pop old flags into rax
    return
writeSector:
;Input:
;ecx = Number of sectors to write
;rdx = Start LBA to write to
    call writeSectorBreak   ;Do break check
    retc                    ;If CF=CY, do not update count or print new msg
    inc qword [secWritten]
    call writeStatusUpdate  ;Update the percentage done message!
    return
writeSectorBreak:
    call checkBreak
    mov al, byte [fmtDrive]     ; Always write to fmtDrive
    mov rbx, qword [pBuffer] ; Memory Buffer address to read from
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