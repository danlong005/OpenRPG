     HDFTACTGRP(*NO)
     Dn                S             10I 0
     Darr              S             10I 0 DIM(3)
     DTMPDSP           S             52A
     C                   EVAL      n = 99
     C                   CLEAR                   n
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   RESET                   n
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   EVAL      arr(1) = 3
     C                   EVAL      arr(2) = 1
     C                   EVAL      arr(3) = 2
     C                   SORTA     arr
     C                   EVAL      TMPDSP = %CHAR(arr(1))
     C     TMPDSP        DSPLY
     C                   EVAL      TMPDSP = %CHAR(arr(2))
     C     TMPDSP        DSPLY
     C                   EVAL      TMPDSP = %CHAR(arr(3))
     C     TMPDSP        DSPLY
     C                   RETURN
