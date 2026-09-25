     HDFTACTGRP(*NO)
     FTESTFL155 UF A F   25        DISK
     DTYPECODE         S              1A
     DTMPDSP           S             52A
     ITESTFL155 AA  01    1 CC
     I                             A    2   21  NAME
     ITESTFL155 AA  02    1 CP
     I                             A    2   21  NAME
      /free
       TYPECODE = 'C';
       NAME = 'Acme Corp';
       EXCEPT;
       TYPECODE = 'P';
       NAME = 'Widget';
       EXCEPT;
      /end-free
     C                   READ      TESTFL155
     C                   DOW       NOT %EOF(TESTFL155)
     C                   IF        *IN01
     C     'cust:'       DSPLY
     C                   ENDIF
     C                   IF        *IN02
     C     'prod:'       DSPLY
     C                   ENDIF
     C                   EVAL      TMPDSP = %TRIM(NAME)
     C     TMPDSP        DSPLY
     C                   READ      TESTFL155
     C                   ENDDO
     C                   RETURN
     OTESTFL155 EADD
     O                       TYPECODE             1
     O                       NAME                21
