     H*Two record types in one program-described file, told apart by
     H*the code in position 1. READ sets on the identified record's
     H*indicator and no other one off, so the program sets both off
     H*before each READ (test441).
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
     C                   EVAL      *IN01 = *OFF
     C                   EVAL      *IN02 = *OFF
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
     C                   EVAL      *IN01 = *OFF
     C                   EVAL      *IN02 = *OFF
     C                   READ      TESTFL155
     C                   ENDDO
     C                   RETURN
     OTESTFL155 EADD
     O                       TYPECODE             1
     O                       NAME                21
