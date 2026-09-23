      /DEFINE FROMCOPY
     DfromCopy         S             10A   INZ('copy')
      /IF DEFINED(FROMCOPY)
     DcopyOnly         S              5I 0 INZ(7)
      /ENDIF
      /EOF
     DafterEof         S             10A   INZ('never')
Nothing after /EOF is read, so this line is never seen as source.
