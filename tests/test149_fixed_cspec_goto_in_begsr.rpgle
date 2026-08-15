     HDFTACTGRP(*NO)
     Dtotal                     10     I0
     C                   EVAL      total = 0
     C                   EXSR      DOIT
     C     %CHAR(total)  DSPLY
     C                   RETURN
     C     DOIT          BEGSR
     C                   EVAL      total = 1
     C                   GOTO      SKIPIT
     C                   EVAL      total = 99
     C                   TAG       SKIPIT
     C                   EVAL      total = total + 10
     C                   ENDSR
