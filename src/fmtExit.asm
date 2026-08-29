;All exits are here, good or bad

exitOk:
    lea rdx, crlfStr    ;Print a CRLF on exit!
    call printString
    mov eax, 4C00h
    int 21h
exitError:
    mov eax, 4C04h
    int 21h
exitNoFormatFixed:
    mov eax, 4C05h
    int 21h

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
badJoinExit:
    lea rdx, badJoinDrv
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
