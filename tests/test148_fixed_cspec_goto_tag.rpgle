     HDFTACTGRP(*NO)
     Dn                         10     I0
     C                   EVAL      n = 0
     C                   TAG       LOOPTOP
     C                   EVAL      n = n + 1
     C     %CHAR(n)      DSPLY
     C                   IF        n < 3
     C                   GOTO      LOOPTOP
     C                   ENDIF
     C                   GOTO      SKIPOVER
     C     'skipped'     DSPLY
     C                   TAG       SKIPOVER
     C     'done'        DSPLY
     C                   RETURN
