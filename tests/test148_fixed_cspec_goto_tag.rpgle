     HDFTACTGRP(*NO)
     Dn                S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      n = 0
     C                   TAG       LOOPTOP
     C                   EVAL      n = n + 1
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   IF        n < 3
     C                   GOTO      LOOPTOP
     C                   ENDIF
     C                   GOTO      SKIPOVER
     C     'skipped'     DSPLY
     C                   TAG       SKIPOVER
     C     'done'        DSPLY
     C                   RETURN
