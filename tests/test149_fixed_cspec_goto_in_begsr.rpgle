     HDFTACTGRP(*NO)
     Dtotal            S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      total = 0
     C                   EXSR      DOIT
     C                   EVAL      TMPDSP = %CHAR(total)
     C     TMPDSP        DSPLY
     C                   RETURN
     C     DOIT          BEGSR
     C                   EVAL      total = 1
     C                   GOTO      SKIPIT
     C                   EVAL      total = 99
     C                   TAG       SKIPIT
     C                   EVAL      total = total + 10
     C                   ENDSR
