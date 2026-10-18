;Misc FAT and File System routines go here

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

setVolumeLabel:
;Sets up the volume label, if the volume label length is geq 0
;Input: rsi -> extBS to write volume label to.
;Output: rsi -> extBS with the volume label.
    push rcx
    movzx ecx, byte [sVolLblCnt]
    test ecx, ecx
    jz .exit
    push rsi
    push rdi
    lea rdi, qword [rsi + extBs.volLab]
    lea rsi, sVolLbl
    rep movsb
    pop rdi
    pop rsi
.exit:
    pop rcx
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
;   dword [fatSize] = eax
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
    mov dword [fatSize], eax
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    return

clust2FATEntry:
;Converts a cluster number to a offset in the FAT
;Entry:  Uses the bpbPtr to convert cluster number
;        eax = Cluster number to look for
;Exit:   eax = Sector on disk of FAT 
;        ecx = 0 => FAT12, 1 => FAT16, 2 => FAT32
;        edx = 1.5Byte/Word/DWord in sector of entry
    push rbx
    push rbp
    mov rbp, qword [bpbPtr]
    movzx ebx, byte [fatType]
    cmp ebx, 1
    jb .fat12
    ja .fat32
;FAT16
    shl eax, 1  ;Multiply cluster number by 2
    push qword 1
    jmp short .common
.fat12:
    mov ecx, eax    ;ecx = eax
    shr ecx, 1      ;ecx = ecx / 2
    add eax, ecx    ;eax = eax + ecx    (eax * 1.5)
    push qword 0
    jmp short .common
.fat32:
    push qword 2
    shl eax, 2  ;Multiply cluster number by 4
.common:
;eax has the FAToffset
    movzx ecx, word [rbp + bpb.bytsPerSec]
    xor edx, edx    ;edx = 0
    div ecx         ;Divide by bytes per sector (0:eax / ecx)
    movzx ebx, word [rbp + bpb.revdSecCnt]   ;Add the offset to the first FAT
    add eax, ebx
    pop rcx ;Pop the FAT type back into rcx
    pop rbp
    pop rbx
    return

cleanBuffer:
;Cleans the 4K buffer
    mov rdi, qword [pBuffer]
    mov ecx, 4096
    xor eax, eax
    rep stosb   ;Clean the Sector buffer
    return

checkDrvFixed:
;Checks if the drive input is fixed
;Input: ebx = Drive number (1-based)
;Output: CF=NC -> Fixed
;        CF=CY -> Removable
    push rax
    push rdx
    mov eax, 4408h  ;Fixed check
    int 21h
    jnc .check
    mov eax, 4409h  ;Net check, default to fixed if something goes awry
    int 21h
    jc .fixed
    test dx, 1000h  ;Is this a net disk?
    jnz .fixed
    jmp short .rem
.check:
    test eax, 1 ;eax = 1 if fixed
    jnz .fixed
.rem:
    stc
    jmp short .exit
    pop rdx
    pop rax
    return
.fixed:
    clc
.exit:
    pop rdx
    pop rax
    return

checkNewPhysFmt:
;Checks if the physical format parameters of the disk have been changed.
;If they are, and the device is of a soft sectored medium (types 0-4), then
; we set the flag.
;Input: 
;   curParams.deviceBPB: As provided by the driver
;   reqParams.deviceBPB: As requested by the user
;Ouput:
;   If Sectors per cluster or Sectors per track changed and the 
;   device is 0-4, set byte [newFormat].
;The physical format parameters are:
; 1) Sectors per cluster (forced to 512 by us, unless 4k byte sectors)
; 2) Sectors per track
    movzx eax, word [curParams + chsParamsBlock.deviceBPB + bpb.bytsPerSec]
    cmp ax, word [reqParams + chsParamsBlock.deviceBPB + bpb.bytsPerSec]
    jne .diff
    movzx eax, word [curParams + chsParamsBlock.deviceBPB + bpb.secPerTrk]
    cmp ax, word [reqParams + chsParamsBlock.deviceBPB + bpb.secPerTrk]
    rete    ;If they are equal, just return
.diff:
    movzx eax, byte [reqParams + chsParamsBlock.bDevType]
    cmp eax, typeHard   ;Everything after this is not ``soft'' sectored
    rete
    cmp eax, typeGenRem
    jne .soft
;Here we do a media sense. If it passes and the drive is 1.44mb, then
; we report newFormat. Else, we return not new Format.
    enter 2, 0
    mov rdx, rbp
    mov bl, byte [fmtDrive]
    inc bl
    mov eax, 440Dh  ;IOCTL
    mov ecx, 0868h  ;Media sense
    int 21h
    movzx eax, word [rdx]   ;Read the word (driver initialises if supported)
    leave
    retc
    cmp ax, 0100h | typeGenRem  ;ah = 01h means floppy
    retne
.soft:
    mov byte [newFormat], -1
    return

;--------------------
; Cool functions
;--------------------
;getLastdrive:
; Gets the size of the CDS array
;    mov edx, -1     ;Undoc! -1 sets the current drive to the current drive!
;    mov eax, 0E00h  ;Set current drive to itself to get the lastdrive value
;    int 21h         ;Just return lastdrive in eax
;    return

