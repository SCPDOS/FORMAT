;All routines used for parsing go here.
;We are flexible on the order of the arguments, switches can go before
; drive letters, we don't enforce an order. No arguments however can be
; multiply set and this constitutes an error.

;Caveats:
;1) /C overrides formatting. It will switch to just reading and writing back
;    each ``bad'' sector. It won't mark sectors as bad.
;2) /F and {/N /T} cannot operate together. This constitutes an error.

parseMain:
    mov eax, 3700h 
    int 21h ;Get in dl the switch char
    mov byte [bSwitch], dl
.skipSwitch:
    mov eax, 6101h  ;Get cmd line arguments
    int 21h ;Get in rdx ptr to the command tail
    lea rsi, qword [rdx + cmdLineArgs.parmList]
    lodsb           ;Get count and point to first char in command tail.
    movzx ecx, al   ;Put count into ecx
    cmp byte [rsi + rcx], CR    ;Is this a valid command line?
    jne badParamExit
.mainLp:
    call skipDelimiters
    je .endParse
    call readChar   ;Get the non-delim char
    cmp al, byte [bSwitch]  ;Is the char the switch char?
    je .switchFnd
;This must be a drive letter and the next char must be a colon, else error.
    movzx edx, al   ;Save the drive letter in dl
    test ecx, ecx   ;A drive letter must be followed by a : 
    jz badParamExit
    call readChar
    cmp al, ":"
    jne badParamExit
;Save the drive letter now. If one was already saved, crap out
    cmp byte [fmtDrive], -1 ;If this is not -1, error
    jne badParamExit
    mov eax, edx    ;Get the possibly lc char back in al for uc-ing
    call ucChar ;Get the UC char in al
    mov byte [cancelL], al      ;Store for cancel string
    mov byte [fmtRemStrL], al   ;And HDD/RemDev strings
    mov byte [fmtHddStrL], al
    sub al, "A"                 ;Convert to a zero based number
    mov byte [fmtDrive], al     ;And store it!
    jmp short .mainLp
.switchFnd:
;Switch char found here. Get the char following the switch
    call readChar
    je badParamExit ;Trailing switch char
    call ucChar     ;Uppercase our switch char in al
    cmp al, "V"
    je .parseVol
;;    cmp al, "T"
;;    je .parseTracks
;;    cmp al, "N"
;;    je .parseSectors
    cmp al, "F"
    je .parseSize
    cmp al, "S"
    je .parseSys
    cmp al, "Q"
    je .parseQuick
    cmp al, "C"
    jne badParamExit
;parse Bad Check here
    test byte [bFlag1], bitBadChck
    jnz badParamExit
    or byte [bFlag1], bitBadChck
    jmp .mainLp
.parseQuick:
    test byte [bFlag1], bitQuick
    jnz badParamExit
    or byte [bFlag1], bitQuick
    jmp .mainLp
.parseSys:
    test byte [bFlag1], bitSystem
    jnz badParamExit
    or byte [bFlag1], bitSystem
    jmp .mainLp
.parseVol:
    test byte [bFlag1], bitVolume
    jnz badParamExit
    or byte [bFlag1], bitVolume
    call readChar
    cmp al, ":"
    jne badParamExit
;Now rsi points to the volume label. We copy a max of 11 chars
    mov edx, 11    ;Use as char counter
    lea rdi, sVolLbl
.pvLp:
    call readChar
    je .endParse    ;If no more chars to read, we are done! Exit parse!
    call isALdelimiter 
    je .mainLp  ;If we read a delimiter, we are done with vol lbl.
    stosb       ;Else, store the volume label char 
    dec edx     ;Drop the count of spaces left.
    jnz .pvLp
    call findDelimiter  ;Might have more chars, skip to the next delim char.
    je .endParse    ;If by doing so run out of chars, exit!
;Now save the length of the volume label and proceed
    neg edx
    add edx, 11     ;Get the length of the volume label
    mov byte [sVolLblLen + 1], dl
    jmp .mainLp
.parseTracks: 
    test word [wGivenTrks], -1      ;If never been accessed, we are 0
    jnz badParamExit
    or byte [bFlag1], bitTrk        ;Now set the bit
    call readChar
    cmp al, ":"
    jne badParamExit
    call getASCIINumber
    cmp ebx, 0FFFFh                 ;Has to be a word
    ja badParamExit
    mov word [wGivenTrks], bx
    jmp .mainLp
.parseSectors:
    test byte [bGivenSPT], -1       ;If never been accessed, we are 0
    jnz badParamExit
    or byte [bFlag1], bitSec
    call readChar
    cmp al, ":"
    jne badParamExit
    call getASCIINumber
    cmp ebx, 0FFh
    ja badParamExit
    mov byte [bGivenSPT], bl
    jmp .mainLp
.parseSize:
    test byte [bFlag1], bitFloppy
    jnz badParamExit
    or byte [bFlag1], bitFloppy
    call readChar
    cmp al, ":"
    jne badParamExit
    call getASCIINumber
    cmp ebx, 0FFFFh 
    ja badParamExit

    push rcx
    lea rdi, szTbl  ;Scan to see if value is between 160 and 720
    mov ecx, szTblL
    mov eax, ebx    ;Search for count in eax
    repne scasw
    je .psFnd
;Here we have either 1.2, 1.44 or 2.88
    pop rcx         ;Get back the char count for ASCII read
    test ecx, ecx
    jz badParamExit
    call readChar
    cmp al, "."
    jne badParamExit
    call getASCIINumber
    push rcx        ;Save it again
    mov ecx, -1     ;Count past the end of the table
    cmp ebx, 2      ;1.2
    je .psFnd
    dec ecx         ;ecx = -1
    cmp ebx, 44     ;1.44
    je .psFnd
    dec ecx         ;ecx = -2
    cmp ebx, 88     ;2.88
    jne badParamExit
.psFnd:
    neg ecx
    lea eax, dword [ecx + szTblL]   ;Turn into bpb table offset
    mov byte [bGivenSz], al
    pop rcx
    jmp .mainLp
.endParse:
    return
;Now we just check that if /F or /T or /N are specified, they are 
; correctly specified.
    test byte [bFlag1], bitSec | bitTrk | bitFloppy 
    retz    ;If none of these bits are set, return ok
    test byte [bFlag1], bitFloppy   ;If this bit not set, ensure both others set
    jz .epST
;Here we know that the floppy bit is set. Ensure neither Sec nor Trk is set too.
    test byte [bFlag1], ~bitFloppy
    retz    ;Return if this is the only bit set
;Fall through here to save 5 bytes as the next cmp will fail!
;.epST:
;Here we know that the floppy bit is not set. Ensure both Sec and Trk bits set
    cmp byte [bFlag1], bitSec | bitTrk
    rete
    jmp badParamExit

parseCheck:
;Checks that the flags we have set make sense for the type of 
; device we are formatting.
;Input: al = Clear if removable
       al = Set if fixed
    test al, al ;All options on rem devs
    retz
;If any of these bits are set, we fail.
    test byte [bFlag1], bitSec | bitTrk | bitFloppy 
    retz
    jmp badParamExit

;-------------------------
; Parse utility functions
;-------------------------

readChar:
;Reads a character from the command tail. 
; If the count goes to zero or CR read, end of line!
;Input: ecx = Number of chars left to read
;       rsi -> String to read
;Output: rsi -> Adv by one char
;        ecx -= 1
;       ZF=ZE: End of cmd tail
;       ZF=NZ: Not end of cmd tail
    test ecx, ecx
    retz
.noCheck:
    lodsb
    dec ecx
    return

findDelimiter:
;Goes to the next delimiter.
;Input: rsi must point to the start of the data string
;       ecx = Number of chars left to to process
;Output: rsi points to the first non-delimiter char
;       ecx = Chars left to process after skipping
;       ZF=ZE: No more chars left to process
;       ZF=NZ: Chars left to process
    push rax
.l1:
    call readChar
    je .exit2
    call isALdelimiter
    jnz .l1
.exit:
    dec rsi ;Point rsi back to the char which is a command delimiter
    inc ecx
.exit2:
    pop rax
    return


skipDelimiters:
;Skips all "standard" command delimiters. This is not the same as FCB 
; command delimiters but a subset thereof. 
;These are the same across all codepages.
;Input: rsi must point to the start of the data string
;       ecx = Number of chars left to to process
;Output: rsi points to the first non-delimiter char
;       ecx = Chars left to process after skipping
;       ZF=ZE: No more chars left to process
;       ZF=NZ: Chars left to process
    push rax
.l1:
    call readChar
    je .exit2
    call isALdelimiter
    jz .l1
.exit:
    dec rsi ;Point rsi back to the char which is not a command delimiter
    inc ecx
.exit2:
    pop rax
    return

isALdelimiter:
;Returns: ZF=NZ if al is not a command separator 
;         ZF=ZE if al is a command separator
    cmp al, SPC
    rete
    cmp al, ";"
    rete
    cmp al, "="
    rete
    cmp al, ","
    rete
    cmp al, TAB
    return

ucChar:
;Input: al = Char to uppercase
;Output: al = Adjusted char 
;Use normal localised uppercase instead of normal uppercase as
; drive letters are in the overlap of normal and filename uc.
;This allows for use of this function beyond just drive letter UC-ing
; (i.e. for switch chars)
    push rdx
    mov edx, eax
    mov eax, 6520h
    int 21h
    mov eax, edx
    pop rdx
    return

getASCIINumber:
;Accumulates the value in ebx and returns it.
;First char read must be a digit, else, we treat a non-digit
; as a terminator of the number. 
;If the value is greater than 32 bits, treat as invalid input
    xor ebx, ebx
    call readChar    ;First char after : must be a digit
    call isAlDigit
    jc badParamExit
.lp:
    and eax, 0Fh    ;Save lower nybble only and zero the rest of the register
    mov ebp, ebx    ;Dont use lea because we cant check for carry
    shl ebx, 2      ;4*ebx
    jc badParamExit
    add ebx, ebp    ;5*ebx
    jc badParamExit
    shl ebx, 1      ;10*ebx
    jc badParamExit
    add ebx, eax    ;Add new digit value
    jc badParamExit
    test ecx, ecx   ;Stop if we run out of chars to process
    retz
    call readChar.noCheck    ;Else get the next char
    call isAlDigit              ;If it is a digit, keep processing
    jnc .lp
;Else, we reset to the first non-digit char and return.
    dec rsi
    inc ecx
    return

isAlDigit:
    cmp al, "0"
    jb .notDigit
    cmp al, "9"
    ja .notDigit
    clc
    return
.notDigit:
    stc 
    return