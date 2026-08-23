     HDFTACTGRP(*NO)
     Dn                         10     I0
     Dtot                       10     I0
     Di                         10     I0
     C                   EVAL      *IN10 = *ON
     C                   EVAL      *IN20 = *OFF
     C   10              EVAL      n = 1
     C   20              EVAL      n = 99
     C  N20              EVAL      tot = 5
     C  N10              EVAL      tot = 99
     C     %CHAR(n)      DSPLY
     C     %CHAR(tot)    DSPLY
     C   10              EXSR      bump
     C   20              EXSR      bump
     C     %CHAR(tot)    DSPLY
     C   10              Z-ADD     42            n
     C     %CHAR(n)      DSPLY
     C   10'cond dsply'  DSPLY
     C  N10'never'       DSPLY
     C   10              EVAL      tot = 1 + 2 + 3 +
     C                             4 + 5
     C     %CHAR(tot)    DSPLY
     C                   EVAL      i = 0
     C                   DOW       i < 10
     C                   EVAL      i = i + 1
     C                   EVAL      *IN30 = i >= 4
     C   30              LEAVE
     C     %CHAR(i)      DSPLY
     C                   ENDDO
     C                   EVAL      i = 0
     C                   DOW       i < 5
     C                   EVAL      i = i + 1
     C                   EVAL      *IN40 = i < 3
     C   40              ITER
     C     %CHAR(i)      DSPLY
     C                   ENDDO
     C   10              GOTO      skip
     C     'skipped=no'  DSPLY
     C                   TAG       skip
     C     'after tag'   DSPLY
     C                   RETURN
     C     bump          BEGSR
     C                   EVAL      tot = tot + 7
     C                   ENDSR
