     HDFTACTGRP(*NO)
     Dn                S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      n = 1
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
      /free
       n = n + 100;
       DSPLY %CHAR(n);
      /end-free
     C                   EVAL      n = n + 1
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   RETURN
