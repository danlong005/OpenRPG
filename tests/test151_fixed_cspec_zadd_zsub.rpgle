     HDFTACTGRP(*NO)
     Dn                S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      n = 999
     C                   Z-ADD     42            n
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   Z-SUB     42            n
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   RETURN
