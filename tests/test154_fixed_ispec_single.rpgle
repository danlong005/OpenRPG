     HDFTACTGRP(*NO)
     FTESTFL154       25           DISK
     ITESTFL154
     I                             A1    20     NAME
     I                             S21   25   0 AGE
     OTESTFL154
     O                       NAME             20
     O                       AGE              25
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
