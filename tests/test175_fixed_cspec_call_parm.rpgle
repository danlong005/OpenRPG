     HDFTACTGRP(*NO)
     Dn                         10     I0
     Dmsg                       10     A
     C                   EVAL      n = 41
     C                   EVAL      msg = 'untouched'
     C                   CALL      'ADDONE'
     C                   PARM                    n
     C                   PARM                    msg
     C     %CHAR(n)      DSPLY
     C     msg           DSPLY
     C                   EVAL      *IN10 = *OFF
     C                   EVAL      n = 100
     C   10              CALL      'ADDONE'
     C                   PARM                    n
     C                   PARM                    msg
     C     %CHAR(n)      DSPLY
     C                   EVAL      *IN10 = *ON
     C   10              CALL      'ADDONE'
     C                   PARM                    n
     C                   PARM                    msg
     C     %CHAR(n)      DSPLY
     C                   RETURN
