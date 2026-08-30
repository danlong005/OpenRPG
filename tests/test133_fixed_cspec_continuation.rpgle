     HDFTACTGRP(*NO)
     Dtotal            S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      total = 1 + 2 + 3 + 4 + 5 + 6 + 7 +
     C                             8 + 9 + 10 + 11 + 12 + 13 + 14 + 15
     C                   EVAL      TMPDSP = %CHAR(total)
     C     TMPDSP        DSPLY
     C                   IF        total > 100 AND total <
     C                             1000
     C     'in range'    DSPLY
     C                   ENDIF
     C                   RETURN
