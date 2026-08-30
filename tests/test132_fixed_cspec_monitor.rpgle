     HDFTACTGRP(*NO)
     Dn                S             10I 0
     C                   MONITOR
     C                   EVAL      n = 42
     C     %CHAR(n)      DSPLY
     C                   ON-ERROR
     C     'caught'      DSPLY
     C                   ENDMON
     C                   RETURN
