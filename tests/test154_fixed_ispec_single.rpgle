     HDFTACTGRP(*NO)
     FTESTFL154 UF A F   25        DISK
     DTMPDSP           S             52A
     ITESTFL154 AA
     I                             A    1   20  NAME
     I                             S   21   25 0AGE
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
     C                   EVAL      TMPDSP = %TRIM(NAME)
     C     TMPDSP        DSPLY
     C                   EVAL      TMPDSP = %CHAR(AGE)
     C     TMPDSP        DSPLY
     C                   READ      TESTFL154
     C                   ENDDO
     C                   RETURN
     OTESTFL154 D
     O                       NAME                20
     O                       AGE                 25
