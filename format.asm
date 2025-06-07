;This is the disk formatting utility for SCP/DOS 1.0
;Uses the undocumented LBA based Generic IO interface

;Supports exactly one command line argument, the drive letter.
;Invoked as so: FORMAT x: where the colon is necessary.

;>>> 7 Steps to Disk Domination <<<
;1) Format begins by turning the drive offline by cleaning the 
;    cdsValidDrive bit in the device CDS. 
;2) Format begins by ascertaining how large the volume/device is.
;    -If the device is removable, format will get the device parameters to 
;      ascertain the size of the volume.
;    -If the device fixed, format will use the VBR to ascertain the size of the 
;      volume and gets device parameters to get the sector size.
;3) Format will then choose which FAT to use and build the BPB accordingly
;    and write it to disk.
;4) Format will then rebuild the disk DPB from the new BPB.
;5) Format will then create two fresh FAT tables.
;6) Format will then clean the root directory (FAT12/16) or allocate a 
;    cluster and sanitise it (FAT32)
;7) Finally, format re-enables cdsValidDrive and exits.

;If a ^C is invoked during the format procedure, we prompt the user 
; for the "are you sure you wish to abandon the format" and that "this may
; result in an unusable volume that will need reformatting" message.
;If they respond with Y, we re-enable the CDS and return to DOS to exit.

;Note Format does not format the full medium and uses Int 25h to read 
; sectors from the old format and Int 26h to write new sectors to the 
; volume. 
;Format also doesnt depend on any old BPB's or anything like so.
;Any old FAT (or other FS) data structures are considered nukable.

[map all ./lst/format.map]
[DEFAULT REL]
BITS 64
%include "./inc/dosMacro.mac"
%include "./inc/dosStruc.inc"
%include "./inc/fatStruc.inc"

struc accFlgBlk
    .bSpecFuncs db ?    ;Must be 0
    .bAccMode   db ?    ;Set if access allowed. Clear if not.
endstruc

struc chsParamsBlock
    .bSpecFuncs db ?    ;Bit 0
    .bDevType   db ?    ;5 if fixed, 7 otherwise
    .wDevFlgs   dw ?    ;Only bits 0 and 1 are xmitted/read
    .wNumCyl    dw ?    ;Num cylinders of media, preserved across calls
    .bMedTyp    db ?    ;Perma 0 for us, meaningless. Reserved.
    .deviceBPB  db 53 dup (?)   ;Full length with reserved bytes of BPB32
    .TrackLayout dw (63*2 + 1) dup (?)  ;Full size table
endstruc
specFuncBPB equ 1<<0    ;In set, locks the BPB. In get, rets backup bpb
;In setBpb, set if we want to lock bpb. clear to unlock
;Below only used in setparams requests. Ignored for getparams 
specFuncTrk equ 1<<1    ;Set if just track layout cpy. Clear if set all.
specFuncSec equ 1<<2    ;Set if all sectors same size. Clear if not.

%include "./src/fmtMain.asm"
%include "./dat/fmtData.asm"
%include "./dat/fmtMsg.asm"
bootloader:
;Symbol pointing to the bootloader
;When building the COM for format, we append the loader binary here