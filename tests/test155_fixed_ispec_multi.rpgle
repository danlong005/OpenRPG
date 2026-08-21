     HDFTACTGRP(*NO)
     FTESTFL155       25           DISK
     ITESTFL155     011     CC
     I                             A2    21     NAME
     ITESTFL155     021     CP
     I                             A2    21     NAME
     DTYPECODE                  1      A
     OTESTFL155
     O                       TYPECODE         1
     O                       NAME             21
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
