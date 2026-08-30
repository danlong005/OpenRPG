     HDFTACTGRP(*NO)
     FTESTFL154 UF A F   25        DISK
     ITESTFL154 AA
     I                             A    1   20  NAME
     I                             S   21   25 0AGE
     OTESTFL154 D
     O                       NAME                20
     O                       AGE                 25
      /free
  NAME = 'Alice';
  AGE = 30;
  WRITE TESTFL154;
  NAME = 'Bob';
  AGE = 25;
  WRITE TESTFL154;
  NAME = 'Carol';
  AGE = 40;
  WRITE TESTFL154;
      /end-free
     C                   READ      TESTFL154
     C                   DOW       NOT %EOF(TESTFL154)
     C     %TRIM(NAME)   DSPLY
     C     %CHAR(AGE)    DSPLY
     C                   READ      TESTFL154
     C                   ENDDO
     C                   RETURN
