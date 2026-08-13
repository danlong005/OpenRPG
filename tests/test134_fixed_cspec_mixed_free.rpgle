     HDFTACTGRP(*NO)
     Dn                         10     I0
     C                   EVAL      n = 1
     C     %CHAR(n)      DSPLY
      /free
  n = n + 100;
  DSPLY %CHAR(n);
      /end-free
     C                   EVAL      n = n + 1
     C     %CHAR(n)      DSPLY
     C                   RETURN
