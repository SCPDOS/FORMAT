;String ops all go the right way on program starup
startFormat:
    jmp short .cVersion
.vNum:          db 1
.cVersion:
;Now check the version!
    mov eax, 3000h
    int 21h
    cmp al, byte [.vNum] ;Version 1
    ja badVerExit
    breakpoint
;Now do reallocation. 
; We always allocate one 4096 byte buffer and a 4096 byte stack.
    lea rbx, bootloader + 2*512 ;Go past the two bootloaders
    mov qword [pBuffer], rbx    ;Use this space as IO buffer
    add rbx, 2*4096             ;Point to the end of this area
    mov rsp, rbx                ;Set the stack pointer home
    sub rbx, r8
    shr rbx, 4
    mov eax, 4A00h      ;Shink always succeeds
    int 21h
    call cleanBuffer    ;Clean the buffer
;Get the verify flag and set it. On exit, reset it!
    mov eax, 5400h  ;Get verify state in al
    int 21h
    mov byte [bVerify], al  ;Save original verify in var
    mov eax, 2E01h  ;Set verify on
    int 21h
;Parsing time :)
    breakpoint
    call parseMain  ;Now parse the command line
;We start with a bold get paramters call to assertain if the drive has
; a FAT. We ignore any failures as this could be a result of the drive 
; being deactivated, in which case we explicitly try to reactivate the drive.
;If further IOCTL errors occur thereonafter, we know the issue is the driver,
; not the CDS.
    call getBpb
    cmp byte [ioParams + chsParamsBlock.deviceBPB + bpb.numFATs], 0
    jne .fatDrv
    mov byte [bCDSAdjust], -1   ;Set the CDS adjustment flag
    mov byte [bValidFS], 0      ;No FAT found
    mov eax, 5F07h
    movzx edx, byte [fmtDrive]
    int 21h
.fatDrv:
;Now ensure the drive we will be formatting is valid
;Check the drive is not a network drive. 
    mov eax, 4409h
    movzx ebx, byte [fmtDrive]
    inc ebx             ;Turn it into a 1 based number
    int 21h
    jnc .netChk
    cmp eax, errInvFnc
    je badIOCTLExit     ;The IOCTL call failed! Crap out
    jmp badDrvExit      ;Else the drive letter was bad!
.netChk:
    test dx, 1200h      ;Is the drive network or shared?
    jnz badNetExit
    test dx, 8000h      ;Is this assigned or substed?
    jnz badSubstExit
;Now we test assign (a front-end subst) by calling truename. This stops front 
; end hooks from swapping letters...
    lea rdi, outputBuffer   ;Large enough for 8 characters
    mov rsi, rdi
    lea eax, dword [ebx + "@" + ((":\") << 8)]
    stosd
    mov eax, 6000h  ;Truename :)
    int 21h
    cmpsd   ;Now compare the two drive letters (the full root paths) :)
    jne badSubstExit
;Now ascertain if removable or not from parameter block.
    test word [ioParams + chsParamsBlock.wDevFlgs], devFixed
    jz .gotRemDev
    mov byte [fixDev], -1   ;Indicate Fixed drive
;If any format specification flags are set for a fixed dev, we fail
    test byte [bFlag1], bitSec | bitTrk | bitFloppy 
    jnz badParamExit
;Verify the volume id
    call verifyVolId        ;ZF=ZE means we proceed with formatting
    jnz badVolumeLabel
;Print the Hard Drive Partition warning string.
    lea rdx, fmtHddStr
    call doYNWait
    jnc goFmt
    mov byte [bRetCde], retNo
    jmp retToDOS   ;CF=CY means no, don't proceed.
.gotRemDev:
;Print the rem dev warning string
    lea rdx, fmtRemStr
    call printString
    call getch  ;Any char will proceed us
goFmt:
;Now hook ^C so that if the user calls ^C we restore DOS state
; (i.e. default drive and reactivate the drive if it is deactivated)
    lea rdx, breakRoutine
    mov eax, 2523h
    int 21h
;Print CRLF and string to signal remdev inserted/fixed disk warning accepted
    lea rdx, fmtMsg ;Now we are about to hit the disk. Print the string
    call printString

    call prepFormat ;Prepares the format information
    call doFormat   ;Do the format track by track (or sector by sector)
    call doFileSys  ;This lays down the file system

    call doSysFiles ;This installs the system files
    call doVolLbl   ;This sets up the volume label, if not specified.
    
    lea rdx, okFormat   ;Successfully formatted!
    call printString   ;Write the disk formatted message
;Now we sync DOS's free cluster count. Warn the user of the possible delay.
    lea rdx, freeSpcStr
    call printString
    mov eax, 3600h  ;Get free space count
    movzx edx, byte [fmtDrive]
    inc edx         ;Turn into a 1 based count
    int 21h
    lea rdx, completeStr    ;Indicate computation done!
    call printString
exitFormat:
    call writeDiskStats     ;Write the stats on the volume we just formatted
    test byte [fixDev], -1  ;Was this drive fixed? Set if so.
    jnz retToDOS
;If we formatted on a remdev, ask if we wanna go again?
exitGoAgain:
    lea rdx, againStr
    call doYNWait
    jc retToDOS  ;If CF=CY, we said no and we are done!
    lea rdx, crlfStr
    call printString    ;Output a new line!
;Reset some internal state and prompt user to insert new media in drive
    mov byte [bRetCde], retOk
    jmp startFormat.gotRemDev


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
    pop rax
    call badExitCleanup
    call resetVerify
    mov eax, 4C00h | retCtrC    ;Tell DOS to terminate with special error level
    push rax
;Let DOS reclaim memory and handles allocated to us
.noAbort:
    mov dl, LF
    call putch
    pop rax
    pop rdx
    iretq   ;Redo the operation

;---------------------------------------
;          DOS Disk wrappers           :
;---------------------------------------
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
    call checkBreak
    mov al, byte [fmtDrive]     ; Always write to fmtDrive
    mov rbx, qword [pBuffer] ; Memory Buffer address to read from
    int 26h
    pop rax ;Pop old flags into rax
    return
doSector:
;Does an IOCTL on a sector.
;Input:
; ecx = IOCTL code for action to enact (Major and Minor code)
; rdx -> Initialised input packet 
;Output: 
; CF=NC: Action carried out ok
; CF=CY: 
    call checkBreak
    push rbx
    push rdx
    movzx ebx, byte [fmtDrive]
    inc ebx
    mov eax, 440Dh      ;Generic IOCTL 
    int 21h
    pop rbx
    return

getBpb:
;Gets the BPB from the bootsector into the buffer
;Input: = al[0] = Set if we return backup bpb. Clear if get from disk.
    mov ecx, 0860h         ;Disk drive type IOCTL, get FAT parameters
    jmp short setBpb.cmn
setBpb:
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

getDriveAccess:
;Get the access status
    lea rdx, accFlgPkt
    mov ecx, 0867h  ;Get Access flag on disk drive
    call daMain
    retc
    cmp al, -1  ;If it is already set, dont mark it as needing setting
    retz
    movzx eax, byte [accFlgPkt + accFlgBlk.bAccMode]
    mov byte [bAccFlag], al
    return
setDriveAccess:
;Set the access flag status to go go go.
    xor eax, eax
    dec eax         ;Set al = -1 for drive access
setDAMain:
;al = Access mode to set the disk to
    lea rdx, accFlgPkt
    mov byte [rdx + accFlgBlk.bAccMode], al
    mov ecx, 0847h  ;Set Access flag on disk drive
daMain:
    movzx ebx, byte [fmtDrive]
    inc ebx ;Turn into a 1 based drive number
    mov eax, 440Dh  ;Generic IOCTL
    int 21h
    return

resetVerify:
;Resets the global verify state back
    movzx eax, byte [bVerify]   ;Get the verify state back
    cmp eax, -1 ;If -1, verify flag not yet modified.
    rete
    or eax, 2E00h
    int 21h
    return
