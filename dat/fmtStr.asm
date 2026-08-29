;Error Messages go here
badVerStr   db "Invalid DOS Version",CR,LF,"$"
badDrvLtr   db "Invalid Drive Specified",CR,LF,"$"
badNetDrv   db "Cannot FORMAT a Network drive",CR,LF,"$"
badSubsDrv  db "Cannot FORMAT a SUBSTed drive",CR,LF,"$"
badJoinDrv  db "Cannot FORMAT a JOINed drive",CR,LF,"$"
badGeneric  db "Cannot Format Drive",CR,LF,"$"

badVolBig   db "Volume too large to format",CR,LF,"$"
badSecSize  db "Invalid Medium Sector Size",CR,LF,"$"
currentFmt  db "Cannot format current drive",CR,LF,"$"
badBtStrWr  db "Unable to write BOOT",CR,LF,"$"
badFSInfoWr db "Unable to write FS Info",CR,LF,"$"
badIOCTL    db "Error in IOCTL call",CR,LF,"$"
badFATWr    db "Error writing FAT",CR,LF,"$"
badDirWr    db "Error writing directory",CR,LF,"$"
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

fmtMsg      db "Formatting...",CR,LF,"$"
fmtPcntMsg  db "% percent formatted...$"
fmtPcntMsgL equ $ - fmtPcntMsg + 3 ;Add three for the max number of digits

againStr    db "Format another (Y/N)? $"
okFormat    db "Format complete",fmtPcntMsgL dup (SPC), CR,LF,"$" 
badFmtFail  db "Format failure",fmtPcntMsgL dup (SPC), CR,LF,"$"

freeSpcStr  db "Calculating free space (this may take several minutes)...",CR,LF,"$"
completeStr db "Complete.",CR,LF,"$"

;Disk stat strings
totalBytesStr       db " bytes total disk space",CR,LF,"$"
sysBytesStr         db " bytes used by system",CR,LF,"$"
badSectStr          db " bytes in bad sectors",CR,LF,"$"
availableBytesStr   db " bytes available on disk",CR,LF,LF,"$"
clustSzStr          db " bytes in each allocation unit.",CR,LF,"$"
totClusStr          db " allocation units available on disk.",CR,LF,LF,"$"
volSerialNumStr     db "Volume Serial Number is $"

;Filename strings
sLblProg db "X:\LABEL.COM",0
sSysProg db "X:\SYS.COM",0