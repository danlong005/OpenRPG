     HDFTACTGRP(*NO)
     Dn                S             10I 0
     DTMPDSP           S             52A
     C                   MONITOR
     C                   EVAL      n = 42
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   ON-ERROR
     C     'caught'      DSPLY
     C                   ENDMON
     C                   RETURN
