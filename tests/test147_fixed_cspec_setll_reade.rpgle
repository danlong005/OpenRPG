     HDFTACTGRP(*NO)
     FCUSTFL147 I    E             DISK    KEYED
     F                                     EXTDESC('custfl147')
     Dkey                       10     A
      /free
  EXEC SQL CREATE TABLE custfl147 (
    CUSTNO VARCHAR(10) PRIMARY KEY,
    CUSTNAME VARCHAR(50)
  );
  EXEC SQL INSERT INTO custfl147 VALUES('B001','Bob1');
  EXEC SQL INSERT INTO custfl147 VALUES('B002','Bob2');
      /end-free
     C                   EVAL      key = 'B002'
     C     key           SETLL     CUSTFL147
     C     key           READE     CUSTFL147
     C                   IF        %FOUND(CUSTFL147)
     C     CUSTNAME      DSPLY
     C                   ENDIF
      /free
  EXEC SQL DROP TABLE custfl147;
      /end-free
     C                   RETURN
