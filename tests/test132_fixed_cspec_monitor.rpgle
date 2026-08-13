     HDFTACTGRP(*NO)
     Dn                         10     I0
     C                   MONITOR
     C                   EVAL      n = 42
     C     %CHAR(n)      DSPLY
     C                   ON-ERROR
     C     'caught'      DSPLY
     C                   ENDMON
     C                   RETURN
