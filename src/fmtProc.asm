;Main routines go here :)

prepFormat:
;Prepares the new file system type. We proceed as follows:
;   If (mediaType == 6)
;       return Fail
;   Copy the ioParams into curParams
;   Copy the ioParams into reqParams
;   Adjust reqParams according to switches
;   Set internal variables for printing
;   newFormat = FALSE
;   If (reqParams.physicalParams != curParams.physicalParams)
;       newFormat = TRUE
;   OGAccFlag = GetAccFlag
;   If (OGAccFlag = Off)
;       SetAccFlag
;   Copy the reqParams to ioParams
    cmp byte [ioParams + chsParamsBlock.bDevType], typeTape
    je badDrvExit
    mov rsi, rdx
    lea rdi, curParams  ;Copy for restoration if things go downhill
    mov ecx, chsParamsBlock_size
    rep movsb
    mov rsi, rdx
    lea rdi, reqParams  ;We will adjust this
    mov ecx, chsParamsBlock_size
    rep movsb
;Setup pointer to the BPB we will be using to report format
    lea rdi, qword [reqParams + chsParamsBlock.deviceBPB] ;Point to BPB
    mov qword [bpbPtr], rdi ;Store this as the BPB buffer pointer
    call switchAdjustBpb    ;If switches set, adjust requested FS
    call prepBPB
    call computeFSVals
;Now we check if the physical parameters (bytes/sector and sector/track)
; have changed 
    call checkNewPhysFmt
    call getDriveAccess ;If call unsupported, the drive is on
    jc .driveOn
    test byte [bAccFlag], -1
    jnz .driveOn
    call setDriveAccess ;Force drive access now!
.driveOn:
    lea rsi, reqParams
    lea rsi, ioParams
    mov ecx, chsParamsBlock_size
    rep movsb
    return

doFormat:
;Now we do the actual format. We proceed according to the following algorithm:
;   setNewFormat
;   If (mediaType != 5 && newFormat == TRUE)
;       If (!formatPossible)
;           return Fail
;       Else
;           doFormat
;   Else
;       doVerify
    mov eax, specFuncBPB            ;Lock the BPB for the update
    call setBpb
    pushfq
    pop rbp                         ;rbp[0] is formatPossible
    cmp word [ioParams + chsParamsBlock.bDevType], typeHard
    jnz .doVerify
    test byte [newFormat], -1
    jnz .doVerify
    test ebp, 1 ;Check if the CF flag was set
    jz .doFormat
;Here, if physical format is not possible or IOCTL format unsupported.
.doFormat:
    mov ecx, 08C2h  ;Do format
    jmp short .doDisk
.doVerify:
    mov ecx, 08E2h  ;Do verify
.doDisk:
    call doSector
    return

doFileSys:
;This routine lays down the file system sectors. If this fails at any point
; the drive is left in an unusable state.
;All calls fail hard from within the function calls.
    mov ebx, 1  ;Set to prepare the variables for writing the new FS sectors
    call prepPrintVals
    cmp byte [fatType], fs_fat32
    jne .noFSstr
    lea rdx, fsWriteStr
    call printString
.noFSstr:
    call writeBS
    call writeFAT
    call writeRootDir
    return

doSysFiles:
    test byte [bFlag1], bitSystem
    retz    ;Don't do if not set
;Read the system files from the root directory of current disk, A:\ or
; the boot disk.
;...
    return
    
doVolLbl:
;Always make a volume label. If the user doesn't want one, no probs.
; If the bit is set, then we used the users volume label when setting
; up the BPB earlier on.
    test byte [bFlag1], bitVolume
    retnz

    return


;----------------------------------------------------
;           Internally linked functions             :
;----------------------------------------------------
computeFSVals:
;Computes various meta-data related to the format we have selected.
;Output:
;   byte [bNumDirSect], number of sectors in the root directory initially
;   dword [dFSAreaSz],  size of reserved section + 2 FATs + initial root dir
;   qword [qDataAreaSz], number of sectors in the data section
    movzx eax, word [rsi + bpb.revdSecCnt]  ;Get reserved count
    mov ebx, eax    ;Set reserved count
    mov eax, dword [fatSize]
    shl eax, 1      ;Multiply this value by 2 for two FATs
    add ebx, eax
    cmp byte [fatType], fs_fat32
    je .fat32
;Add the sectors for the root directory
    mov rsi, qword [bpbPtr]
    movzx eax, word [rsi + bpb.rootEntCnt]  ;Number of 32 bit entries
    shl eax, 5  ;Get number of bytes in root dir
    movzx esi, word [rsi + bpb.bytsPerSec]
    xor edx, edx
    div esi ;Get number of whole sectors in eax. edx is remainder. 
    test edx, edx   ;If no remainder (should never be a remainder), proceed
    jz .final
    inc rax  ;Add one for remainder
.final:
;Come here with rbx = rolling count of sectors and 
; al = Number of sectors in the root directory initially.
    mov byte [bNumDirSect], al
    add rbx, rax    ;Add to rolling count
    mov dword [dFSAreaSz], ebx
    mov rax, qword [numSectors]
    sub rax, rbx
    mov qword [qDataAreaSz], rax
    return
.fat32:
    movzx eax, byte [secPerClust]   ;Sectors per cluster (1 cluster for dir)
    jmp short .final

writeBS:
;This cleans the reserved section and writes the 
; bootsector we provided the driver to disk.
    call cleanBuffer
    movzx esi, word [ioParams + chsParamsBlock.deviceBPB + bpb.revdSecCnt]
.clean:
    xor edx, edx
    lea ecx, dword [edx + 1]
    call writeSector
    jc badBtSctrExit
    dec esi
    jnz .clean
;Now we copy the bootloader into the sector buffer for writing 
    mov rsi, qword [pBtLdr]
    mov rdi, qword [pBuffer]
    mov ecx, 512
    rep movsb
;Now we write the boot sector
    mov ecx, 1      ;ecx = Number of sectors to write
    xor edx, edx    ;rdx = Start LBA to write to
    call writeSector
    jc badBtSctrExit
    cmp byte [fatType], fs_fat32  ;If not FAT32, skip backup bootsector
    retne
;------------------
;Do FAT32 here
;------------------
;Now we write the backup BPB too at sector 6
    mov ecx, 1  ;1 Sector to write
    mov edx, 6  ;At sector 6
    call writeSector
    jnc .doFSInfo
;If something goes wrong writing the backup, set the backup bootsector 
; to sector 0 as the standard allows this and proceed.
    mov word [rbx + + oemHeader_size + bpb32.BkBootSec], 0
    mov ecx, 1      ;ecx = Number of sectors to write
    xor edx, edx    ;rdx = Start LBA to write to
    call writeSector
    jc badBtSctrExit   ;If this fails, it means bs is being dodgy. Fail!
.doFSInfo:
;Now write the FS Info sectors
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
    return

writeFAT:
;This routine cleans the FAT sectors and sets up the signature.
;Unlocks the BPB
    mov eax, ~specFuncBPB    ;Unlock the BPB
    call setBpb    ;Finish by syncing the BPB again
    jc badFormatExit
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
.fatFillLoop:
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
    jnz .fatFillLoop
    return

writeRootDir:
;Sets up the root directory on the disk.
;Correctly selects a good cluster for FAT32 root directories.
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
    return
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
    call writeSector
    pop rdx
    pop rcx
    jc badDirExit
    add edx, dword [rdi + bpb32.FATsz32]   ;Go to backup FAT sector
    push rdx
    call writeSector
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
    return

prepBPB:
;Selects a file system for the medium and makes a correct bootsector 
; for it. Sets up necessary internal variables.
;Input: rdi -> Current BPB as reported by the driver.
;       qword [bpbPtr] = Same as rdi.
;       
;Output: Update the BPB pointed to by rdi.
;        Set all internal BPB vars.
;
;We trust the returned BPB even for FAT12 floppies, as even if the media 
; doesn't have a BPB on it, the driver will return one to us. The format 
; operation will then lay a fresh BPB on the media too.
;This means we convert old floppies to the new, better format.
;We also convert all drives to 512 bytes (unless it has 4096).

;Start by ensuring that we always set the number of FATs to 2!
    mov byte [rdi + bpb.numFATs], 2
    ;movzx ebx, word [rdi + bpb.bytsPerSec]
    ;mov word [sectorSize], bx 
    mov word [sectorSize], 512
    movzx eax, byte [rdi + bpb.media]
    mov byte [media], al
    movzx eax, byte [rdi + bpb.secPerClus]  ;Store the reported secPerClus val
    mov byte [secPerClust], al
    mov eax, dword [rdi + bpb.hiddSec]
    mov dword [hiddSector], eax
    movzx eax, word [rdi + bpb.totSec16]
    mov ecx, dword [rdi + bpb.totSec32]
    test eax, eax   ;If totSec16 is 0, use totSec32
    cmovz eax, ecx
    mov qword [numSectors], rax

    lea rbx, bootloader     ;Now set the source bootloader.
    mov qword [pBtLdr], rbx ;And store it. If FAT32, we will adjust below
;Now we select the FAT based on the size of the volume.
;If a hard drive, it is automatically a FAT 16 or 32 media.
fatSelect:
    mov byte [fatType], fs_fat12   ;Init fatType to be FAT 12
    test byte [fixDev], -1
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
    lea rsi, genericBPB12
    ;movzx eax, byte [secPerClust]
    mov eax, 1     ;Sect/Clust is always 1 for FAT12
    jmp .fat12
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
    mov ebx, dword [rsi]
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
;rsi points to the table entry
    cmp byte [fatType], fs_fat32
    je .fat32
    mov al, byte [rsi + 4]  ;Get the sector per cluster value in al
.fat12:
;Now we copy the correct generic bpb into the CHS IOCTL param block
;al = Sector per cluster count
    lea rsi, genericBPB16   ;rsi -> appropriate generic BPB 
    mov ecx, bpb_size
    call .adjBPB
    mov word [rdi + bpb.FATsz16], ax
    jmp short .bpbReady
.fat32:
    mov al, byte [rsi + 8]  ;Get the sector per cluster value in al
    lea rsi, genericBPB32   ;rsi -> appropriate generic BPB
    add qword [pBtLdr], 200h ;Go past the first bootsector in memory
    mov ecx, bpb32_size
    call .adjBPB
    mov dword [rdi + bpb32.FATsz32], eax
    mov word [rdi + bpb32.extFlags], 0  ;FAT mirroring active
    mov dword [rdi + bpb32.RootClus], 2 ;Set cluster 2 to root. May adjust
.bpbReady:
;Entered with rdi -> bpb to write to and cl = BPB size
    lea rsi, qword [rdi + rcx]    ;Point to dest extBPB to use
;Now setup the extended BPB fields.
    movzx eax, byte [fixDev]
    and eax, 80h ;Save only bit 7
    mov word [rsi + extBs.drvNum], ax   ;Clear the reserved field too
    call setVolumeLabel ;Sets up a volume label, if one was provided.
    call getVolumeID    ;Gets a fresh ID in eax
    mov dword [rsi + extBs.volId], eax
    mov dword [dSerNum], eax  ;Save the serial number
    return
.adjBPB:
;Updates the BPB in reqPkt to the values based on input arguments and 
; our modifications.
;Input: al = Sector per cluster value to set ``byte [secPerClust]'' to
;       cl = BPB size
;       rsi -> Source of the BPB to initialise with
;       qword [bpbPtr] -> Which BPB to write to (reqPkt)
;Output: rdi -> Updated BPB 
;                   (media, hiddSec, sectorSize, Bytes/Sector, Sector/Cluster)
;        rsi -> Source of extended BPB 
;        eax = FAT size
;eax, edx destroyed
    push rcx
    mov byte [secPerClust], al
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
    xor ecx, ecx
    xor edx, edx
    cmp eax, 0FFFFh
    cmovb ecx, eax  ;If below, cx = ax, edx = 0
    cmovnb edx, eax ;If not below, cx = 0, edx = eax
    mov word [rdi + bpb.totSec16], cx
    mov dword [rdi + bpb.totSec32], edx
    call computeFATSize
    pop rcx
    return

switchAdjustBpb:
;Selects an alternative BPB to use as the default
    test byte [bFlag1], bitFloppy | bitSec | bitTrk
    retz    ;Do nothing if none of the flags are set
    test byte [bFlag1], bitFloppy
    jnz .doFloppy
;Here we have a /T/N combo. We create a BPB based on these entries.
.doFloppy:
;Here we have a /F so we use the offset into the table.
    return

verifyVolId:
;Check the root directory for a volume label. If one exists, ask the
; user to confirm the volume ID. If they can't type it in, we crap them out.
;Input: Nothing
;Output: ZF=ZE: Proceed with format
;        ZF=NZ: Abort format!
    lea rdx, volIdFcb
    movzx eax, byte [fmtDrive]
    mov byte [rdx + exFcb.driveNum], al
    mov eax, 1100h  ;Find First FCB
    int 21h
    inc al  ;If al = -1, then inc sets the zero flag
    retz
;The DTA has the Find First block with the volume label
    lea rdx, volLblStr
    call printString 
    lea rdx, inputBuffer
    mov word [rdx], 12          ;Allow for 11 chars + CR terminator
    mov eax, 0A00h
    int 21h                     ;Take buffered input 
    lea rdx, qword [rdx + 2]    ;Point rdx to the string itself
    movzx ecx, byte [rdx - 1]   ;Get the string length
    mov eax, 65A1h              ;Filename uppercase the ecx chars at rdx
    int 21h
    mov rsi, rdx
    mov eax, 2F00h              ;Get DTA ptr in rbx
    int 21h
    lea rdi, qword [rbx + exFcb.filename]
    repe cmpsb
    return

makeBS:
;Makes a bootsector from the newly initialised bpb @ bpbPtr
    mov rbx, qword [pBuffer]    
    mov rdi, rbx    ;Point rdi to the buffer
;Now copy the default bootsector into the buffer. We require 512 byte
; boot sectors. If the sector size of the medium is less than 512 bytes
; then we skip the boot sector writing phase, instead just copying the
; BPB to the sector at the normal location. The jump bytes are 0 too.
    cmp word [sectorSize], 512
    jae .doBS
;Here we got to put the oem stuff in the bs so that DOS's driver will
; recognise the bootsector as valid. Thus we have valid sector 0's for
; weird sectord devices. 
    mov dword [rbx + oemHeader.jump], 090FEEBh ;Infinite loop jump!
    mov rax, "SCPDOSv1"
    mov qword [rbx + oemHeader.oemString], rax
    jmp short .noBS
.doBS:
;If sector size 1024 or 4096, the bytes after 512 are zeroed.
    mov rsi, qword [pBtLdr]
    mov ecx, 512
    rep movsb   ;Copy the bootsector into the sector buffer
;Mark as a valid bootsector but also mark to SCPBIOS as not SCPBIOS bootable!
    mov byte [rbx + 509], 0 ;Make the disk not bootable
    mov word [rbx + 510], 0AA55h
.noBS:
;Now copy the accurate BPB into the bootsector
    lea rdi, qword [rbx + 11]    ;Point rdi to the BPB in the sector
    mov rsi, qword [bpbPtr]
    movzx ecx, byte [bpbSize]   ;Now copy the bpb
    rep movsb
    return