;Data area here
fmtDrive    db -1       ;Drive we are operating on (0 based)
inCrit      db 0        ;If not 0, in a critical section, must exit
cdsPtr      dq 0        ;CDS ptr here
pBuffer     dq 0        ;Ptr to the buffer area
bFlag1      db 0 | bitQuick ;HARDCODED TO BE QUICK FORMAT FOR NOW
pBtLdr      dq 0        ;Point to the bootloader to use
bSwitch     db "/"      ;Switch char

;Switch vars
sVolLblLen  db 12, 0    ;Start of the string buffer
sVolLbl     db 12 dup (SPC) ;Volume label goes here.
wGivenTrks  dw 0        ;Tracks per side (1 head as remdev)
bGivenSPT   db 0        ;Sectors per track
bGivenSz    db 0        ;This is an offset into the BPB table if /F set

;Format Data here
remDev      db 0        ;0 = Removable, -1 = Fixed
fatType     db -1       ;0 = FAT12, 1 = FAT16, 2 = FAT32, -1 = No FAT
sectorSize  dw 512      ;Sector size in bytes: HARDCODED BYTES PER SECTOR VALUE
numSectors  dq 0        ;Number of sectors in volume
secPerClust db 0        ;Copy the sectors per cluster over
fatSize     dd 0        ;FAT size (number of sectors per FAT)
media       db 0F0h     ;Media type (F0h or F8h)
bpbPtr      dq 0        ;Pointer to the buffer for the BPB (in IOCTL block)
bpbSize     db 0        ;Size of the BPB
hiddSector  dd 0        ;Only used for Fixed Disks, offset to add
f32RootClus dd 0        ;Cluster addr of the root dir cluster if FAT32
dSerNum     dd 0        ;Serial number
dBadClust   dd 0        ;Number of bad clusters on disk

;Tracking vars, used only for updating the percentage message!
secToWrite  dq 0        ;Number of sectors to write (neq numSectors if /Q set)
secWritten  dq 0        ;Number of sectors written so far
secPercent  db -1       ;The previous percentage (-1 not initialised)

;Tables
;All data here is RO.
;Each row is 5 bytes, {DWORD, BYTE} with DWORD = diskSize, BYTE=secPerClusVal
;This table assumes a 512 byte sector (fair assumption) but we do a byte size
; comparison in format to eventually allow for other sized sectors
fat16ClusterTable:
    dd 8400*512 ;Disks up to 4.1MB, must use FAT12 with 0.5 K clusters
    db 1    ;ALL FAT12 uses 1, unless it is a preexisting meddesc type medium
    dd 32680*512    ; Disk up to 16MB, 1K clusters
    db 2
    dd 262144*512   ; Disk up to 128MB, 2K clusters
    db 4
    dd 524288*512   ; Disk up to 256MB, 4K clusters
    db 8
    dd 1048576*512  ; Disk up to 512Mb, 8K clusters
    db 16

;Here DWORD becomes QWORD
fat32ClusterTable:
    dq 16777216*512 ; Disk up to 8GB, 4K clusters
    db 8        
    dq 33554432*512 ; Disk up to 16GB, 8K clusters
    db 16
    dq 67108864*512 ; Disk up to 32Gb, 16K clusters
    db 32
    dq -1       ; Disk up to 2TB, 32K clusters
    db 64

;Bpbs are for remdevs of 160Kb to 2.88Mb capacity.
;We have these built-in so that if /F:160 to /F:2.88
; is selected, we can format to these standard values. 
bpbTbl:
bpb160Kb:
    istruc bpb  ;160Kb 5.25" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 1    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 64   ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 320  ;Number of sectors on medium
        at .media,      db 0FEh ;Media descriptor byte
        at .FATsz16,    dw 1    ;Number of sectors per FAT
        at .secPerTrk,  dw 8    ;Number of sectors per "track"
        at .numHeads,   dw 1    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors
    iend
bpb180Kb:
    istruc bpb  ;180Kb 5.25" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 1    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 64   ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 360  ;Number of sectors on medium
        at .media,      db 0FCh ;Media descriptor byte
        at .FATsz16,    dw 2    ;Number of sectors per FAT
        at .secPerTrk,  dw 9    ;Number of sectors per "track"
        at .numHeads,   dw 1    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors
    iend
bpb320Kb:
    istruc bpb  ;320Kb 5.25" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 2    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 112  ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 640  ;Number of sectors on medium
        at .media,      db 0FFh ;Media descriptor byte
        at .FATsz16,    dw 1    ;Number of sectors per FAT
        at .secPerTrk,  dw 8    ;Number of sectors per "track"
        at .numHeads,   dw 2    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors
    iend
bpb360Kb:
    istruc bpb  ;360Kb 5.25" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 2    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 112  ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 720  ;Number of sectors on medium
        at .media,      db 0FDh ;Media descriptor byte
        at .FATsz16,    dw 2    ;Number of sectors per FAT
        at .secPerTrk,  dw 9    ;Number of sectors per "track"
        at .numHeads,   dw 2    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors
    iend
bpb720Kb:
    istruc bpb  ;720Kb 3.5" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 2    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 112  ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 1440 ;Number of sectors on medium
        at .media,      db 0F9h ;Media descriptor byte
        at .FATsz16,    dw 3    ;Number of sectors per FAT
        at .secPerTrk,  dw 9    ;Number of sectors per "track"
        at .numHeads,   dw 2    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors
    iend
bpb120Mb:
    istruc bpb  ;1.2Mb 5.25" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 1    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 224  ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 2400 ;Number of sectors on medium
        at .media,      db 0F9h ;Media descriptor byte
        at .FATsz16,    dw 7    ;Number of sectors per FAT
        at .secPerTrk,  dw 15   ;Number of sectors per "track"
        at .numHeads,   dw 2    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors
    iend
bpb144Mb:
    istruc bpb  ;1.44Mb 3.5" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 1    ;Sectors per cluster
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 224  ;Number of 32 byte entries in Root directory  
        at .totSec16,   dw 2880 ;Number of sectors on medium   
        at .media,      db 0F0h ;Media descriptor byte   
        at .FATsz16,    dw 9    ;Number of sectors per FAT
        at .secPerTrk,  dw 18   ;Number of sectors per "track" 
        at .numHeads,   dw 2    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors 
    iend
bpb288Mb:
    istruc bpb  ;2.88Mb 3.5" floppies
        at .bytsPerSec, dw 512  ;Bytes per sector
        at .secPerClus, db 2    ;To be FAT 12 OK, we need 2 sectors/clust
        at .revdSecCnt, dw 1    ;Number of reserved sectors, in volume
        at .numFATs,    db 2    ;Number of FATs on media
        at .rootEntCnt, dw 224  ;Number of 32 byte entries in Root directory
        at .totSec16,   dw 5760 ;Number of sectors on medium 
        at .media,      db 0F0h ;Media descriptor byte 
        at .FATsz16,    dw 18   ;Number of sectors per FAT
        at .secPerTrk,  dw 36   ;Number of sectors per "track" 
        at .numHeads,   dw 2    ;Number of read "heads"
        at .hiddSec,    dd 0    ;Number of hidden sectors
        at .totSec32,   dd 0    ;32 bit count of sectors   
    iend

;Generic BPBs here, fields set to -1 must be edited in the copy made.
genericBPB12:
    istruc bpb
        at .bytsPerSec, dw -1   ;512 bytes per sector, normally
        at .secPerClus, db -1   ;1 sector per cluster, normally
        at .revdSecCnt, dw 1    ;1 Reserved Sector
        at .numFATs,    db 2    ;2 FAT tables
        at .rootEntCnt, dw 224  ;224 root entries
        at .totSec16,   dw -1   ;Total number of sectors on disk
        at .media,      db 0F0h ;Media byte
        at .FATsz16,    dw -1   ;9 FAT sectors, normally
        at .secPerTrk,  dw 18   ;18 Sectors per track
        at .numHeads,   dw 2    ;2 Heads
        at .hiddSec,    dd -1   ;No hidden sectors on removable
        at .totSec32,   dd 0    ;16 bit entry suffices
    iend
    istruc extBs 
        at .drvNum,     db -1   ;Set to 0 for Remdev, 80h for fixed disk
        at .reserved1,  db 00h
        at .bootSig,    db extBsSig ;Normal signature
        at .volId,      dd -1       ;Set to date/time @ format
        at .volLab,     db 'NO NAME    '    
        at .filSysType, db 'FAT12   '
    iend


genericBPB16:
    istruc bpb
        at .bytsPerSec, dw -1   ;512 bytes per sector, normally
        at .secPerClus, db -1   ;Sectors per cluster
        at .revdSecCnt, dw 1    ;1 Reserved Sector
        at .numFATs,    db 2    ;2 FAT tables
        at .rootEntCnt, dw 512  ;512 root entries
        at .totSec16,   dw -1   ;Total number of sectors on disk
        at .media,      db 0F0h ;Media byte
        at .FATsz16,    dw -1   ;Number of sectors per FAT
        at .secPerTrk,  dw 03Fh ;FAT16 and 32 have Hard disk geometry 
        at .numHeads,   dw 0FFh ;255 Heads
        at .hiddSec,    dd -1   ;No hidden sectors on removable
        at .totSec32,   dd 0    ;16 bit entry suffices
    iend
    istruc extBs 
        at .drvNum,     db -1   ;Set to 0 for Remdev, 80h for fixed disk
        at .reserved1,  db 0
        at .bootSig,    db extBsSig ;Normal signature
        at .volId,      dd -1       ;Set to date/time @ format
        at .volLab,     db 'NO NAME    '    
        at .filSysType, db 'FAT16   '
    iend
gbs_size equ ($ - genericBPB16) + 11

genericBPB32:
    istruc bpb32
        at .bytsPerSec, dw -1   ;512 bytes per sector, normally
        at .secPerClus, db -1   ;Sectors per cluster
        at .revdSecCnt, dw 16   ;16 Reserved Sectors
        at .numFATs,    db 2    ;2 FAT tables
        at .rootEntCnt, dw 0    ;Invalid field for FAT32
        at .totSec16,   dw 0    ;Not a FAT 12/16 BPB
        at .media,      db 0F0h ;Media byte
        at .FATsz16,    dw 0    ;Not a FAT 12/16 BPB
        at .secPerTrk,  dw 03Fh ;FAT16 and 32 have Hard disk geometry 
        at .numHeads,   dw 0FFh ;255 Heads
        at .hiddSec,    dd -1   ;No hidden sectors on removable
        at .totSec32,   dd -1   ;Total number of sectors on disk
;---------------------FAT 32 SPECIFIC FIELDS---------------------
        at .FATsz32,    dd -1  ;Number of sectors per FAT
        at .extFlags,   dw -1  ;Extended Flags word
        at .FSver,      dw 0   ;File system version word, must be 0
        at .RootClus,   dd -1  ;First Cluster of Root Directory
        at .FSinfo,     dw 1   ;Sector number of FSINFO structure, usually 1
        at .BkBootSec,  dw 6   ;Backup Boot sector, either 0 or 6
        at .reserved,   db 12 dup (0) ;Reserved 12 bytes
    iend
    istruc extBs 
        at .drvNum,     db -1   ;Set to 0 for Remdev, 80h for fixed disk
        at .reserved1,  db 0
        at .bootSig,    db extBsSig ;Normal signature
        at .volId,      dd -1       ;Set to date/time @ format
        at .volLab,     db 'NO NAME    '    
        at .filSysType, db 'FAT32   '
    iend
gbs32_size equ ($ - genericBPB32) + 11


accFlgPkt:
    istruc accFlgBlk
        at .bSpecFuncs, db 0
        at .bAccMode,   db 0    ;If 0, disable access. If -1, enable.
    iend
ioParams:
    istruc chsParamsBlock
    at .bSpecFuncs, db 4    ;Bit 0 = Dont lock bpb. Bit 2 = Sectors same size.
    at .bDevType,   db 0    ;5 if fixed, 7 otherwise
    at .wDevFlgs,   dw 0    ;Only bits 0 and 1 are xmitted/read
    at .wNumCyl,    dw 63
    at .bMedTyp,    db 0    ;Perma 0 for us, meaningless. Reserved.
    at .deviceBPB,  db 53 dup (0)   ;Full length with reserved bytes of BPB32
    at .TrackLayout,    dw 63
;Each row is a pair of words:
;   dw Sector number, Sector size
    dw 1, 200h
    dw 2, 200h
    dw 3, 200h
    dw 4, 200h
    dw 5, 200h
    dw 6, 200h
    dw 7, 200h
    dw 8, 200h
    dw 9, 200h
    dw 10, 200h
    dw 11, 200h
    dw 12, 200h
    dw 13, 200h
    dw 14, 200h
    dw 15, 200h
    dw 16, 200h
    dw 17, 200h
    dw 18, 200h
    dw 19, 200h
    dw 20, 200h
    dw 21, 200h
    dw 22, 200h
    dw 23, 200h
    dw 24, 200h
    dw 25, 200h
    dw 26, 200h
    dw 27, 200h
    dw 28, 200h
    dw 29, 200h
    dw 30, 200h
    dw 31, 200h
    dw 32, 200h
    dw 33, 200h
    dw 34, 200h
    dw 35, 200h
    dw 36, 200h
    dw 37, 200h
    dw 38, 200h
    dw 39, 200h
    dw 40, 200h
    dw 41, 200h
    dw 42, 200h
    dw 43, 200h
    dw 44, 200h
    dw 45, 200h
    dw 46, 200h
    dw 47, 200h
    dw 48, 200h
    dw 49, 200h
    dw 50, 200h
    dw 51, 200h
    dw 52, 200h
    dw 53, 200h
    dw 54, 200h
    dw 55, 200h
    dw 56, 200h
    dw 57, 200h
    dw 58, 200h
    dw 59, 200h
    dw 60, 200h
    dw 61, 200h
    dw 62, 200h
    dw 63, 200h
    iend
