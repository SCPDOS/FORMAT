;Put switchable procedures that are part of format here.

doSysFiles:
    test byte [bFlag1], bitSystem
    retz    ;Don't do if not set
;Read the system files from the root directory of current disk.
    return
    
doVolLbl:
;Always make a volume label. If the user doesn't want one, no probs.
; If the bit is set, use the volume label given by user.
    test byte [bFlag1], bitVolume
    jnz .promptLbl
    lea rdi, 
.promptLbl:

    return

doSectorCheck:
    return