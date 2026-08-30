     HDFTACTGRP(*NO)
     FCUSTFL144 IF   E             DISK    KEYED
     F                                     EXTDESC('CUSTFL144')
     Dkey              S             10A
      /free
  EXEC SQL CREATE TABLE custfl144 (
    CUSTNO VARCHAR(10) PRIMARY KEY,
    CUSTNAME VARCHAR(50)
  );
  EXEC SQL INSERT INTO custfl144 VALUES('C001','Alice');
  EXEC SQL INSERT INTO custfl144 VALUES('C002','Bob');
      /end-free
     C                   EVAL      key = 'C002'
     C     key           CHAIN     CUSTFL144
     C                   IF        %FOUND(CUSTFL144)
     C     CUSTNAME      DSPLY
     C                   ENDIF
     C                   EVAL      key = 'Z999'
     C     key           CHAIN     CUSTFL144
     C                   IF        NOT %FOUND(CUSTFL144)
     C     'not found'   DSPLY
     C                   ENDIF
      /free
  EXEC SQL DROP TABLE custfl144;
      /end-free
     C                   RETURN
