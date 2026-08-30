     HDFTACTGRP(*NO)
     Dn                S             10I 0
     Dmsg              S             10A
     DTMPDSP           S             52A
     C                   EVAL      n = 41
     C                   EVAL      msg = 'untouched'
     C                   CALL      'ADDONE'
     C                   PARM                    n
     C                   PARM                    msg
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C     msg           DSPLY
     C                   EVAL      *IN10 = *OFF
     C                   EVAL      n = 100
     C   10              CALL      'ADDONE'
     C                   PARM                    n
     C                   PARM                    msg
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   EVAL      *IN10 = *ON
     C   10              CALL      'ADDONE'
     C                   PARM                    n
     C                   PARM                    msg
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   RETURN
