;Error Messages go here
badParamStr db "Invalid parameter$"
badVerStr   db "Invalid DOS Version$"
badDrvLtr   db "Invalid Drive Specified$"
badNetDrv   db "Cannot FORMAT a Network drive$"
badSubsDrv  db "Cannot FORMAT an ASSIGNed or SUBSTed drive$"

badVolBig   db "Volume too large to format$"
badSecSize  db "Invalid Medium Sector Size$"
badBtStrWr  db "Unable to write BOOT$"
badFSInfoWr db "Unable to write FS Info$"
badFATWr    db "Error writing FAT$"
badDirWr    db "Error writing directory$"
badIOCTL    db "Error in IOCTL call$"
badWP       db "Attempted write-protect violation$"
badFSstr    db "Invalid media or File System area bad - disk unusable$"
badVolLbl   db "Invalid Volume ID$"

;Removable device warning message
fmtRemStr   db "Insert new Media for drive "
fmtRemStrL  db "#:",CR,LF,"and strike ENTER when ready$"
;Hard drive warning message
fmtHddStr   db CR,LF,"WARNING! ALL DATA ON NON-REMOVABLE DISK",CR,LF, "DRIVE "
fmtHddStrL  db "#: WILL BE LOST!",CR,LF,"Proceed with Format (Y/N)? $"
;CTRL+C message
cancel      db CR,LF,"Are you sure you wish to abort formatting drive "
cancelL     db "#?", CR,LF
            db "Doing so may result in an unusable volume. Y/N?$"

crlfStr     db CR,LF,"$"
crlfStr2    db CR,LF,LF,"$"

fmtMsg      db CR,LF,"Formatting...",CR,LF,"$"
fmtPcntMsg  db "% percent formatted...$"
fmtPcntMsgL equ $ - fmtPcntMsg + 3 ;Add three for the max number of digits

againStr    db "Format another (Y/N)? $"
okFormat    db "Format complete",fmtPcntMsgL dup (SPC), CR,LF,"$" 
badFmtFail  db "Format failure",fmtPcntMsgL dup (SPC), CR,LF,"$"

fsWriteStr  db "Writing out file allocation table",CR,LF,"$"
fsWPcntMsg  db "% percent written...$"
fsWPcntMsg equ $ - fmtPcntMsg + 3


freeSpcStr  db "Calculating free space (this may take several minutes)...",CR,LF,"$"
completeStr db "Complete.",fsWPcntMsg dup (SPC),CR,LF,"$"

volLblStr   db "Enter current Volume Label for drive"
volDrv      db "_: $"

;Disk stat strings
totalBytesStr       db " bytes total disk space",CR,LF,"$"
sysBytesStr         db " bytes used by system",CR,LF,"$"
badSectStr          db " bytes in bad sectors",CR,LF,"$"
availableBytesStr   db " bytes available on disk",CR,LF,LF,"$"
clustSzStr          db " bytes in each allocation unit.",CR,LF,"$"
totClusStr          db " allocation units available on disk.",CR,LF,LF,"$"
volSerialNumStr     db "Volume Serial Number is $"

;Filename strings
sSysProg db "X:\SYS.COM",0

;Size strings to check for if /F: specified.
fStrings:
;The strings below are in a matrix.
;Dword = Number of strings in the sub-matrix
;sArray = Dword many ASCIIZ strings for comparison.
;
;Table is ended with a null word

;160K format
    dd 3
    db 3,"160"
    db 4,"160K"
    db 5,"160KB"
;180K format
    dd 3
    db 3,"180"
    db 4,"180K"
    db 5,"180KB"
;320K format
    dd 3
    db 3,"320"
    db 4,"320K"
    db 5,"320KB"
;360K format
    dd 3
    db 3,"360"
    db 4,"360K"
    db 5,"360KB"
;720K format
    dd 3
    db 3,"720"
    db 4,"720K"
    db 5,"720KB"
;1.2M format
    dd 6
    db 4,"1200"
    db 5,"1200K"
    db 6,"1200KB"
    db 3,"1.2"
    db 4,"1.2M"
    db 5,"1.2MB"
;1.44M format
    dd 6
    db 4,"1440"
    db 5,"1440K"
    db 6,"1440KB"
    db 4,"1.44"
    db 5,"1.44M"
    db 6,"1.44MB"
;2.88M format
    dd 6
    db 4,"2880"
    db 5,"2880K"
    db 6,"2880KB"
    db 4,"2.88"
    db 5,"2.88M"
    db 6,"2.88MB"
;End of table
    dd 0