;All exits are here, good or bad
badDrvExit:
    lea rdx, badDrvLtr
    jmp short badParamExit.drv
badParamExit:
    lea rdx, badParamStr
.drv:
    mov byte [bRetCde], retParm
    jmp exitError

;Below here set the generic error code
badFSSpace:
    lea rdx, badFSstr
    jmp badExitSetErr
badVerExit:
    lea rdx, badVerStr
    jmp badExitSetErr
badVolumeLabel:
    lea rdx, badVolLbl
    call printString
    jmp badFormatExit
;---------------------------------------------------------
; The following four exits need to be adjusted with the
; string order swapped! The writing of these sectors
; DONT happen with a percentage count so we need to swap
; the order of the printing.
;---------------------------------------------------------
badBtSctrExit:
    call restoreBpb     ;Handle BPB driver state restore
    lea rdx, badFmtFail
    call printString
    lea rdx, badBtStrWr 
    jmp badExitSetErr
badFATExit:
    lea rdx, badFmtFail
    call printString
    lea rdx, badFATWr
    jmp short badExitSetErr
badDirExit:
    lea rdx, badFmtFail
    call printString
    lea rdx, badDirWr
    jmp short badExitSetErr
badFSINFOExit:
    lea rdx, badFmtFail
    call printString
    lea rdx, badFSInfoWr
    jmp short badExitSetErr
;---------------------------------------------------------

badIOCTLExit:
    lea rdx, badIOCTL
    jmp short badExitSetErr
badVolExit:
    lea rdx, badVolBig
    jmp short badExitSetErr
badSecSizeExit:
    lea rdx, badSecSize
    jmp short badExitSetErr
badNetExit:
    lea rdx, badNetDrv
    jmp short badExitSetErr
badSubstExit:
    lea rdx, badSubsDrv
    jmp short badExitSetErr
badFormatExit:
    lea rdx, badFmtFail
    call printString
badExitSetErr:
;Exits through here set the generic error code
    mov byte [bRetCde], retErr
exitError:
;Jumped to with rdx = Error message
    call printString
    call badExitCleanup
retToDOS:
;Return through here
    call resetVerify
    lea rdx, crlfStr2           ;Print two new lines on exit.
    call printString
    movzx eax, byte [bRetCde]   ;Get the return code
    or eax, 4C00h               ;Tell DOS we wanna quit!
    int 21h

badExitCleanup:
;Let the verify flag be reset in the successful exit part.
;Resets all other global state we touch :)
    movsx eax, byte [bAccFlag]
    inc eax      ;We only reset the value if it was initially turned off!
    jz .skipDriveAccessReset
    call setDAMain  ;Else, reset the access value back to the value in eax
.skipDriveAccessReset:
    test byte [bCDSAdjust], -1  ;Return if we never touched this 
    retz
    mov eax, 5F08h          ;Deactivate CDS if there was no DOS detected FAT.
    movzx edx, byte [fmtDrive]
	int	21h		
    return
    
restoreBpb:
;Gets the BPB from the bootsector again to restore the driver state.
    mov eax, specFuncBPB    ;Get the backup bpb (which is old prev bpb)
    call getBpb
    jnc .gotBpb
;If we cant even get the BS anymore, lock drive (if fixed).
    test byte [fixDev], -1
    retz
    xor eax, eax    ;Prevent drive access now
    jmp setDAMain
.gotBpb:
;Now sync it back
    mov eax, specFuncBPB
    call setBpb
    mov eax, ~specFuncBPB
    call setBpb
    return