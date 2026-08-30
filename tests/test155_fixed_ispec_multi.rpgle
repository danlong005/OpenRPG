     HDFTACTGRP(*NO)
     FTESTFL155 UF A F   25        DISK
     ITESTFL155 AA  01    1 CC
     I                             A    2   21  NAME
     ITESTFL155 AA  02    1 CP
     I                             A    2   21  NAME
     DTYPECODE         S              1A
      /free
       TYPECODE = 'C';
       NAME = 'Acme Corp';
       WRITE TESTFL155;
       TYPECODE = 'P';
       NAME = 'Widget';
       WRITE TESTFL155;
      /end-free
     C                   READ      TESTFL155
     C                   DOW       NOT %EOF(TESTFL155)
     C                   IF        *IN01
     C     'cust:'       DSPLY
     C                   ENDIF
     C                   IF        *IN02
     C     'prod:'       DSPLY
     C                   ENDIF
     C     %TRIM(NAME)   DSPLY
     C                   READ      TESTFL155
     C                   ENDDO
     C                   RETURN
     OTESTFL155 D
     O                       TYPECODE             1
     O                       NAME                21
