;All routines used for parsing go here.
;We are flexible on the order of the arguments, switches can go before
; drive letters, we don't enforce an order. No arguments however can be
; multiply set and this constitutes an error.
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
.mainLp:
    call skipDelimiters
    je .endParse
    cmp al, byte [bSwitch]  ;Is the char the switch char?
    je .switchFnd
;This must be a drive letter and the next char must be a colon, else error.
    movzx edx, al  ;Save the drive letter in dl
    call readChar 
    je badParamExit ;Cannot end with just a letter
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
;parse Bad Check here
    test byte [bFlag1], bitBadChck
    jnz badParamExit
    or byte [bFlag1], bitBadChck
    jmp short .mainLp
.parseQuick:
    test byte [bFlag1], bitQuick
    jnz badParamExit
    or byte [bFlag1], bitQuick
    jmp short .mainLp
.parseSys:
    test byte [bFlag1], bitSystem
    jnz badParamExit
    or byte [bFlag1], bitSystem
    jmp short .mainLp
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
    or byte [bFlag1], bitSecTrk     ;Now set the bit
    call readChar
    cmp al, ":"
    jne badParamExit
    ;TO BE FILLED IN
.parseSectors:
    test byte [bGivenSPT], -1       ;If never been accessed, we are 0
    jnz badParamExit
    or byte [bFlag1], bitSecTrk
    call readChar
    cmp al, ":"
    jne badParamExit
    ;TO BE FILLED IN
.parseSize:
    test byte [bFlag1], bitFloppy
    jnz badParamExit
    or byte [bFlag1], bitFloppy
    call readChar
    cmp al, ":"
    jne badParamExit
;rsi points to the portion of the command that specifies the size
;Should be three or four chars

.endParse:


readChar:
;Reads a character from the command tail. 
; If the count goes to zero or CR read, end of line!
;Input: ecx = Number of chars left to read
;       rsi -> String to read
;Output: rsi -> Adv by one char
;        ecx -= 1
;       ZF=ZE: End of cmd tail
;       ZF=NZ: Not end of cmd tail
    lodsb
    dec ecx
    retz
    cmp al, CR
    retz

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