     H*A READ of a program-described file sets on the indicator of the
     H*record type it identified, and turns no other one off; at end of
     H*file it changes none (PUB400, 2026-10-21).
     HDFTACTGRP(*NO)
     FTESTFL441 UF A F   25        DISK
     DTYPECODE         S              1A
     DR                S             40A
     ITESTFL441 AA  01    1 CC
     I                             A    2   21  NAME
     ITESTFL441 AA  02    1 CP
     I                             A    2   21  NAME
      /free
       TYPECODE = 'C';
       NAME = 'Acme';
       EXCEPT;
       TYPECODE = 'P';
       NAME = 'Widget';
       EXCEPT;
       TYPECODE = 'C';
       NAME = 'Beta';
       EXCEPT;
      /end-free
     C                   READ      TESTFL441
     C                   DOW       NOT %EOF(TESTFL441)
     C                   EVAL      R = %TRIM(NAME) + ' 01=' + %CHAR(*IN01)
     C                             + ' 02=' + %CHAR(*IN02)
     C     R             DSPLY
     C                   READ      TESTFL441
     C                   ENDDO
     C                   EVAL      R = 'eof 01=' + %CHAR(*IN01)
     C                             + ' 02=' + %CHAR(*IN02)
     C     R             DSPLY
     C                   EVAL      *INLR = *ON
     C                   RETURN
     OTESTFL441 EADD
     O                       TYPECODE             1
     O                       NAME                21
