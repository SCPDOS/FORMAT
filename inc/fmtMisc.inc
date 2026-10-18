;Misc equates and strucs go here :)


;Default behaviour is to always zero all data sectors of the disk as well. 
; This is done to also pick up bad clusters to mark them as bad in the FAT.
bitQuick    equ 1   ;/Q -> Do quick format, no zeroing. No bad sect. checks.
bitSystem   equ 2   ;/S -> Install system files. 
;Checks: current drive:\currentdir, A:\ [copies whole files into memory]
bitVolume   equ 4   ;/V:[LABEL] -> Don't prompt volume, use LABEL directly.
bitBadChck  equ 8   ;/C -> Checks if bad clusters are still bad. 
; If this is specified, doesn't format the disk.
;Next three hold only on remdevs. If these bits set on fixed disk, bad parm!
;-----------------------------------v
bitSec      equ 10  ;/N:<Sectors>.  | These two must both be set, else
bitTrk      equ 20  ;/T:<Tracks>.   |  bad parameter! Suppose double sided
;-----------------------------------^
bitFloppy   equ 40  ;/F:<size> -> Specify the size of volume. 
;Options are: 160, 180, 320, 360, 720, 1.2, 1.44, 2.88 (written as strings)
;Either /F Floppy is set or {/N /T}. Not both!
;bitClean    equ 80  ;/P:<count> -> Overwrite each sector ``count'' times
; with random numbers. If /P:0 specified, then clean once with 0's.
;/Q trumps /P and if both specified, /Q is accepted.

;Return values from FORMAT
retOk   equ 0   ;Return all ok!
retParm equ 1   ;Return bad parameters were selected
retCtrC equ 3   ;Return on Crtl+C
retErr  equ 4   ;Return generic error 
retNo   equ 5   ;Return user selected no on a Y/N question
retDNR  equ 6   ;Return Drive not ready
retWP   equ 7   ;Return write protected

;Some FORMAT specific equates
fs_fat12 equ 0
fs_fat16 equ 1
fs_fat32 equ 2

;---------------------:
; Some useful structs :
;---------------------:
struc exFcb
    .extSig     db ?  ;If the first byte is -1, signals an exFCB
    .reserved   db 5 dup (?)  
    .attribute  db ?  ;File attribute byte
    .driveNum   db ?  ;0 based drive number
    .filename   db 8 dup (?)
    .fileext    db 3 dup (?)
    .curBlock   db 2 dup (?)  ;Current block number relative to 0
;One block consists of 128 records, of size denoted in the below
    .recordSize db 2 dup (?)  ;Record size, default 80h
    .fileSize   db 4 dup (?)  ;File size, in bytes
    .fileDate   db 2 dup (?)  ;Standard date format
    .fileTime   db 2 dup (?)  ;Standard time format
    ;----------------------------------------
    ;Internal Records
    .sftNdx     db ?  ;Internal, SFT ndx number
    .fcbMode    db ?  ;Internal byte, to indicate format of special field
    .special    db 6 dup (?)
    ;----------------------------------------
    .recordNum  db ?  ;Current record in block
    .randRecrd  db 4 dup (?)  ;Relative record number, relative to start of file
endstruc

struc cmdLineArgs
    .fcb1       db 16 dup (?)  ;First FCB,    argument 1 
    .fcb2       db 20 dup (?)  ;Second FCB,   argument 2
    .dta:   ;Pointer to the default DTA in the PSP
    .parmList   db ?   ;Number of characters in command tail
    .progTail   db 127 dup (?) ;Default DTA/Program tail
endstruc

struc execProg 
    .pEnv       dq ?    ;Ptr to environment block (or 0 => copy parent env)
    .pCmdLine   dq ?  ;Ptr to the command line to be placed at PSP + 80h
    .pfcb1      dq ?  ;Ptr to the first FCB (parsed argument 1)
    .pfcb2      dq ?  ;Ptr to the second FCB  (parsed argument 2)
endstruc

struc accFlgBlk
    .bSpecFuncs db ?    ;Must be 0
    .bAccMode   db ?    ;Set if access allowed. Clear if not.
endstruc

maxTrackSz  equ 63

struc chsParamsBlock
    .bSpecFuncs db ?
    .bDevType   db ?    ;5 if fixed, 7 otherwise
    .wDevFlgs   dw ?    ;Only bits 0 and 1 are xmitted/read
    .wNumCyl    dw ?    ;Num cylinders of media, preserved across calls
    .bMedTyp    db ?    ;Perma 0 for us, meaningless. Reserved.
    .deviceBPB  db 53 dup (?)   ;Full length with reserved bytes of BPB32
    .TrackLayout:
endstruc
specFuncBPB equ 1<<0    ;In set, locks the BPB. In get, rets backup bpb
;In setBpb, set if we want to lock bpb. clear to unlock
;Below only used in setparams requests. Ignored for getparams 
specFuncTrk equ 1<<1    ;Set if just track layout cpy. Clear if set all.
specFuncSec equ 1<<2    ;Set if all sectors same size. Clear if not.
;Necessary DevFlgs
devFixed    equ 1       ;Set if fixed disk 

struc trackTable
    .wArraySz   dw ?    ;Number of entries in the array
    .sTrackArray:       ;An array of the below struc
endstruc

struc trackTableRow
    .wSectorId  dw ?    ;Sector number (1 - Max id in track)
    .wSectorSz  dw ?    ;Given as a byte count (i.e. 512 for 512 bytes)
endstruc

struc lbaFormatBlock
    .bSize          db ?
    .bNumSectors    db ?  ;# sectors to act on. Returns sectors acted on
    .sRes           db 6 dup (?)
    .qStartSector   dq ?  ;Sector to start action on
endstruc

;Device types in the chs parameter block
;Device Type flags
type48TPI   equ 0   ;Small floppy format, depreciated
type96TPI   equ 1   ;Large floppy format, depreciated
typeSmall   equ 2   ;Super large floppy format, depreciated
type8InchSS equ 3   ;8" single sided floppy format, depreciated
type8InchDS equ 4   ;8" double sided floppy format, depreciated
typeTape    equ 6   ;Tape drive, depreciated
typeOptical equ 8   ;Optical drive, unused
type288     equ 9   ;2.88Mb floppy, depreciated
;The above are not completely supported by this version of the driver.
typeHard    equ 5   ;Hard drive
typeGenRem  equ 7   ;Generic removable medium, default