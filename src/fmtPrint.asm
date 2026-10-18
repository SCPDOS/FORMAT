
;Printing and status output preparation routines go here

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

doYNWait:
;This does the below but also outputs a new line to 
; indicate that input has been recieved.
    call .doWait
    pushfq
    lea rdx, crlfStr
    call printString    ;Output a new line!
    popfq
    return
.doWait:
;Input: rdx -> String to wait for Y/N on.
;Output: CF=NC -> Y(es)
;        CF=CY -> N(o)
    push rdx
    call printString
    call getch
    movzx edx, al
    mov eax, 6523h  ;Zeros upper word of lower dword
    int 21h
    pop rdx
    cmp eax, 1
    ja .doWait
    return

;--------------------------------------
;          Utility functions          :
;--------------------------------------
writeDiskStats:
;Writes the disk statistics after a format.
;-------------------------------------------------------
;<Number> bytes total disk space
;<Number> bytes used by system (if /S set and system files installed)
;<Number> bytes in bad sectors (if bad sectors. Always rounds to # of clusters)
;<Number> bytes available on disk 
;
;<Number> bytes in each allocation unit.
;<Number> allocation units available on disk. ;alloc units are clusters
;
;Volume Serial Number is <Serial-Number>
;-------------------------------------------------------
;Start start by putting a new line
    lea rdx, crlfStr
    call printString
;Start by getting free sector count from DOS. We do this to make the 
; computation of the free sector count easier after /s and if any bad clusters.
    mov eax, 3600h  ;Get free space count
    movzx edx, byte [fmtDrive]
    inc edx ;Turn into a 1 based count
    int 21h
;If we have a FAT 32 drive, add one cluster to the free count to account for
; the root directory cluster.
    cmp byte [fatType], fs_fat32
    jne .goSave
    inc ebx ;Discount the root directory from initial count!
.goSave:
;Use x64 regs instead of stack frame
    mov r8, rdx ;r8 = Total cluster count in data area
    mov r9, rbx ;r9 = Free cluster count in the data area
;Total number of bytes, ebx still has total count
    movzx eax, byte [secPerClust]
    movzx ecx, word [sectorSize]
    mul ecx     ;Get the number of bytes per cluster in eax
    mov r10, rax    ;Save this value in r10
    mul r8      ;Get in eax the number of bytes on disk
    call printDecimalDword
    lea rdx, totalBytesStr
    call printString
;System bytes
    test byte [bFlag1], bitSystem
    jz .skipSystem
    mov rcx, r9     ;Get the free cluster count
    mov rax, r8     ;Get the total cluster count
    sub eax, ecx    ;Workout the amount of space taken by system files
    mov rcx, r10    ;Get word BytesPerClust
    mul ecx         ;Get the number of bytes taken by system files
    call printDecimalDword
    lea rdx, sysBytesStr
    call printString
.skipSystem:
;Bad cluster bytes
    mov ecx, dword [dBadClust]
    test ecx, ecx
    jz .skipBad
    mov rax, r8     ;Get the total cluster count
    sub eax, ecx
    mov rcx, r10    ;Get word BytesPerClust
    mul ecx         ;Get the number of bytes taken by bad clusters
    call printDecimalDword
    lea rdx, badSectStr
    call printString
.skipBad:
;Free bytes
    mov rax, r9     ;Get free cluster count
    mov rcx, r10    ;Get word BytesPerClust
    mul ecx         ;Get the number of free bytes
    call printDecimalDword
    lea rdx, availableBytesStr
    call printString
;Bytes per cluster
    mov rax, r10    ;Get word BytesPerClust
    call printDecimalDword
    lea rdx, clustSzStr
    call printString
;Number of clusters
    mov rax, r8     ;Get the total cluster count
    call printDecimalDword
    lea rdx, totClusStr
    call printString
;Vol Serial Number
    lea rdx, volSerialNumStr
    call printString
    lea rsi, qword [dSerNum]
    lodsb
    call printHexByte
    lodsb
    call printHexByte
    mov edx, "-"
    call putch
    lodsb
    call printHexByte
    lodsb
    call printHexByte
;We are done so print a new line :)
    lea rdx, crlfStr
    call printString    ;Output a new line!
    return

printHexByte:
    lea rbx, .tbl
    push rax
    shr eax, 4  ;Move nybble down
    call .phn
    pop rax
    call .phn
    return
.phn:
;Prints hex nybble in al.
    and eax, 0Fh    ;Save lower nybble only
    xlatb
    mov edx, eax
    call putch
    return
.tbl    db "0123456789ABCDEF"

updateStatus:
;Used to update the number of sectors processed and update the message
; if appropriate.
    inc qword [secDone]
    push rcx
    push rdx
    mov rax, qword [secDone]
    mov ebx, 100
    mul rbx ;Multiply number of sectors by 100
    mov rbx, qword [secToDo]
    xor edx, edx
    div rbx ;Get percentage of sectors processed in rax (formally al)
    cmp al, byte [secPercent]
    je .exit    ;If they are equal, dont bother printing again
;Here we have a new percentage! Update the message!
    mov byte [secPercent], al
    mov ecx, 3  ;Max 3 chars to print (up to 100)
    call printDecimalValLB
    lea rdx, fmtPcntMsg
    call printString
    mov dl, CR
    call putch  ;End by returning to the start of the line
.exit:
    pop rdx
    pop rcx
    return 

printDecimalDword:
    push rcx
    mov ecx, 17 ;Need to make space for dword + commas
    call printDecimalValLB
    pop rcx
    return
printDecimalValLB:
;Takes a value in rax and prints it's decimal representation with leading
; blanks and inserts commas where appropriate.
;Input: rax = Value to print
;       rcx = Buffer size to handle (usual values: 17 for max, 13 for dword)
    mov rbp, rsp
    sub rsp, rcx ;Allocate the buffer on the stack
    mov rdi, rbp
    sub rdi, rcx
    push rax
    push rcx
    push rdi
    xor eax, eax
    rep stosb   ;Initialise the buffer with a null value
    pop rdi     ;Now set the ptr to the head of the buffer
    pop rcx
    pop rax
    push rcx    ;Save this value to keep the buffer length
    call decimalise   ;If return with CF=CY, error!
    pop rcx     ;Now print the buffer
    mov rdi, rbp
    dec rdi     ;Doesn't affect CF
    jc .errPrint    ;Print a mis-aligned ? to clearly mark an error!
.skipLp:
    mov bl, byte [rdi]
    test bl, bl ;Any leading null's get replaced with a space
    jne .printLp
    mov dl, " "
    call putch
    dec rdi
    dec ecx
    cmp ecx, 1
    jne .skipLp   ;Always print 1 byte for size
.printLp:
    mov dl, byte [rdi]
    call putch
    dec rdi
    dec ecx
    jnz .printLp
.exit:
    mov rsp, rbp    ;Deallocate the buffer and exit!
    return
.errPrint:
;Print a default ? symbol if an overflow occurs.
    mov dl, "?"
    call putch
    jmp short .exit

decimalise:
;Input: rax = value to decimalise
;       rdi -> Ptr to byte buffer to store string in with commas
;       ecx = buffer length
;Output: Buffer @ rdi filled in! 
;       ecx = Number of chars in buffer.
; Warning: If the number of chars in the buffer reaches buffer length,
;   we return with CF=CY. Else, CF=NC.
    push rdi
    mov esi, ecx    
    xor ecx, ecx    ;Use cl as buffer length ctr, ch as comma ctr
    mov ebx, 0Ah    ;Divide by 10
.lp:
    cmp ch, 3       ;Are we divisible by 3?
    jne .skipSep
    cmp sil, cl
    je .exitErr     ;Before we add a comma, do we have space?
    ;mov dl, byte [ctryData + countryStruc.thouSep]
    ;mov byte [rdi], dl
    mov byte [rdi], ","
    inc rdi 
    inc cl          ;Inc number of chars
    xor ch, ch      ;Reset comma counter
.skipSep:
    cmp sil, cl
    je .exitErr     ;Before we add a digit, do we have space?
    xor edx, edx
    div rbx         ;Divide rax by 10
    add dl, "0"     
    mov byte [rdi], dl
    inc rdi
    inc cl          ;Inc number of chars
    inc ch          ;Inc to keep track of commas
    test rax, rax
    jnz .lp
;The test cleared CF if we are here
    movzx ecx, cl
.exit:
    pop rdi
    return
.exitErr:
    stc
    jmp short .exit

prepPrintVals:
;Compute secToDo and initialise secDone and secPercent.
;Input: ebx = 0 means prep for one full verify
;       ebx = 1 means prep for verify, clean, and write of file system area
;Output: vars initialised.
    xor eax, eax
    mov qword [secDone], rax   ;Initialised for when multiple formats
    mov byte [secPercent], -1
    test ebx, ebx
    jz .verify
;File system area. We do the full computation at once.
    mov eax, dword [dFSAreaSz]  ;Get write count
    test byte [bFlag1], bitQuick
    jnz .exit
;Not a quick format, so add the verification pass too
    shl eax, 1  ;Multiply by 2
.exit:
    mov qword [secToDo], rax
    return
.verify:
    mov rax, qword [qDataAreaSz]
    jmp short .exit
