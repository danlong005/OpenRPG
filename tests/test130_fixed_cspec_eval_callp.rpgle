     HDFTACTGRP(*NO)
     Dtotal            S             10I 0
     Dmsg              S              5A
     Di                S             10I 0
     C                   EVAL      total = 5 + 3
     C                   EVALR     msg = 'HI'
     C                   FOR       i = 1 TO 6
     C                   IF        i = 3
     C                   ITER
     C                   ENDIF
     C                   IF        i = 5
     C                   LEAVE
     C                   ENDIF
     C     %CHAR(i)      DSPLY
     C                   ENDFOR
     C     msg           DSPLY
     C                   CALLP     doubleIt(total)
     C                   RETURN
      /free
       DCL-PR doubleIt;
         n INT(10) VALUE;
       END-PR;
       DCL-PROC doubleIt;
         DCL-PI doubleIt;
           n INT(10) VALUE;
         END-PI;
         DSPLY %CHAR(n * 2);
       END-PROC;
      /end-free
