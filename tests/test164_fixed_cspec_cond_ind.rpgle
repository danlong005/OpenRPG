     HDFTACTGRP(*NO)
     Dn                S             10I 0
     Dtot              S             10I 0
     Di                S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      *IN10 = *ON
     C                   EVAL      *IN20 = *OFF
     C   10              EVAL      n = 1
     C   20              EVAL      n = 99
     C  N20              EVAL      tot = 5
     C  N10              EVAL      tot = 99
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C                   EVAL      TMPDSP = %CHAR(tot)
     C     TMPDSP        DSPLY
     C   10              EXSR      bump
     C   20              EXSR      bump
     C                   EVAL      TMPDSP = %CHAR(tot)
     C     TMPDSP        DSPLY
     C   10              Z-ADD     42            n
     C                   EVAL      TMPDSP = %CHAR(n)
     C     TMPDSP        DSPLY
     C   10'cond dsply'  DSPLY
     C  N10'never'       DSPLY
     C   10              EVAL      tot = 1 + 2 + 3 +
     C                             4 + 5
     C                   EVAL      TMPDSP = %CHAR(tot)
     C     TMPDSP        DSPLY
     C                   EVAL      i = 0
     C                   DOW       i < 10
     C                   EVAL      i = i + 1
     C                   EVAL      *IN30 = i >= 4
     C   30              LEAVE
     C                   EVAL      TMPDSP = %CHAR(i)
     C     TMPDSP        DSPLY
     C                   ENDDO
     C                   EVAL      i = 0
     C                   DOW       i < 5
     C                   EVAL      i = i + 1
     C                   EVAL      *IN40 = i < 3
     C   40              ITER
     C                   EVAL      TMPDSP = %CHAR(i)
     C     TMPDSP        DSPLY
     C                   ENDDO
     C   10              GOTO      skip
     C     'skipped=no'  DSPLY
     C     skip          TAG
     C     'after tag'   DSPLY
     C                   RETURN
     C     bump          BEGSR
     C                   EVAL      tot = tot + 7
     C                   ENDSR
