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
    cmp al, "T"
    je .parseTracks
    cmp al, "N"
    je .parseSectors
    cmp al, "F"
    je .parseSize
    cmp al, "S"
    je .parseSys
    cmp al, "Q"
    je .parseQuick
    cmp al, "C"
    jne badParamExit
;Parse Bad Check here. Bad check overrides everything.
    test byte [bFlag1], bitBadChck
    jnz badParamExit
    mov byte [bFlag1], bitBadChck
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
    mov byte [sVolLblCnt], 0    ;Reset the volume label count!
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
    mov byte [sVolLblCnt], dl
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
;Now we read ahead. Max string length is 6, min is 2 so we first figure out the
; end of the string. If it is outside this length, we fail. Else we copy the string
; and then null terminate and go through the table.
    enter 8, 0      ;Make sufficient space on the stack for the string
    lea rdi, qword [rbp - 8]    ;Store the chars here
    mov rdx, rdi    ;Save the ptr to the head of the string in rbx
    mov ebx, 7      ;Use as a char counter. If it goes above 6, fail!
.parseFLp:
    call readChar   
    jz .parseFLpEnd
    call isALdelimiter
    jz .parseFLpEnd
    dec ebx
    jz badParamExit ;If we are about to store a 7th char, fail!
    stosb
    jmp short .parseFLp
.parseFLpEnd:
    cmp ebx, 5
    jae badParamExit    ;If we stored 0, 1 or 2 chars, fail!
    push rcx            ;Save the number of chars left to process on stack
    push rsi            ;rsi now points past the /F: string. Save it!
    mov ecx, 7
    sub ecx, ebx        ;Get the number of chars stored in ecx!
    mov eax, 6521h      ;Uppercase ASCIIZ pointed to by rdx
    int 21h
    mov rdi, rdx        ;Point rdi to the capitalised string
    lea rsi, fStrings
.parseFSearchLp:
    lodsd           ;Read the leading dword of the table and adv rsi
    test eax, eax
    jz badParamExit ;If we get here, the string didn't match. Bad parameter!
    mov ebx, eax    ;This is the count of strings for this sub table
.parseFSearchLp2:
    lodsb           ;Get the length of the string to compare in al
    movzx ecx, al   ;rsi points to the string. Set ecx = chars to compare
    mov rdi, rdx    ;Point rdi to the start of the user string now
    push rcx
    push rsi
    repe cmpsb      ;Compare table string with given string
    pop rsi
    pop rcx
    je .parseFSearchLpEnd
    add rsi, rcx    ;Go to the next string in the sub-matrix
    dec ebx         ;Drop another entry from the sub-matrix count
    jnz .parseFSearchLp2    
    inc byte [bGivenSz]         ;Go to next BPB table now!
    jmp short .parseFSearchLp   ;Go to next sub-matrix
.parseFSearchLpEnd:
    pop rsi
    pop rcx
    leave
    jmp .mainLp
.endParse:
;Now we just check that if /F or /T or /N are specified, they are 
; correctly specified, i.e. either /F or {/T and /N}.
    test byte [bFlag1], bitSec | bitTrk | bitFloppy 
    retz    ;If none of these bits are set, return ok
    test byte [bFlag1], bitFloppy   ;If this bit not set, ensure both others set
    jz .epST
;Here we know that the floppy bit is set. Ensure neither Sec nor Trk is set too.
    test byte [bFlag1], ~bitFloppy
    retz    ;Return if this is the only bit set
;Fall through here to save 5 bytes as the next cmp will fail!
.epST:
;Here we know that the floppy bit is not set. Ensure both Sec and Trk bits set
    cmp byte [bFlag1], bitSec | bitTrk
    rete
    jmp badParamExit

;-------------------------
; Parse utility functions
;-------------------------

readChar:
;Reads a character from the command tail. 
; If the count is zero, end of line!
;Input: ecx = Number of chars left to read
;       rsi -> String to read
;Output:
;       ZF=NZ: Not end of cmd tail 
;           rsi += 1
;           ecx -= 1
;       ZF=ZE: End of cmd tail

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