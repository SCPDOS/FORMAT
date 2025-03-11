;Messages go here
badVerStr   db "Invalid DOS Version",CR,LF,"$"
badDrvLtr   db "Invalid Drive Specified",CR,LF,"$"
badRedir    db "Cannot Format Redir, Subst or Join Drives",CR,LF,"$"
badGeneric  db "Cannot Format Drive",CR,LF,"$"
cancel      db "Are you sure you wish to abort formatting drive "
cancelL     db "#?", CR,LF
            db "Doing so may result in an unusable volume. Y/N?",CR,LF,"$"
badVolBig   db "Volume too large to format",CR,LF,"$"
badSecSize  db "Invalid Medium Sector Size",CR,LF,"$"
okFormat    db "Format complete",CR,LF,"$"
currentFmt  db "Cannot format current drive",CR,LF,"$"
badBtStrWr  db "Unable to write BOOT",CR,LF,"$"
badIOCTL    db "Error in IOCTL call",CR,LF,"$"

;Removable device warning message
fmtRemStr   db "Insert new Media for drive "
fmtRemStrL  db "#: and strike ENTER when ready$"
;Hard drive warning message
fmtHddStr   db "WARNING! ALL DATA ON NON-REMOVABLE DISK",CR,LF, "DRIVE "
fmtHddStrL  db "#: WILL BE LOST!",CR,LF,"Proceed with Format (Y/N)?"