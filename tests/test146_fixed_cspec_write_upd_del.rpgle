     HDFTACTGRP(*NO)
     FCUSTFL146 I    E             DISK    KEYED
     F                                     EXTDESC('custfl146')
     Dkey                       10     A
      /free
  EXEC SQL CREATE TABLE custfl146 (
    CUSTNO VARCHAR(10) PRIMARY KEY,
    CUSTNAME VARCHAR(50)
  );
      /end-free
     C                   EVAL      CUSTNO = 'W001'
     C                   EVAL      CUSTNAME = 'WriteTest'
     C                   WRITE     CUSTFL146
     C                   EVAL      key = 'W001'
     C     key           CHAIN     CUSTFL146
     C                   IF        %FOUND(CUSTFL146)
     C     CUSTNAME      DSPLY
     C                   ENDIF
     C                   EVAL      CUSTNAME = 'Updated'
     C                   UPDATE    CUSTFL146
     C     key           CHAIN     CUSTFL146
     C                   IF        %FOUND(CUSTFL146)
     C     CUSTNAME      DSPLY
     C                   ENDIF
     C                   DELETE    CUSTFL146
     C     key           CHAIN     CUSTFL146
     C                   IF        NOT %FOUND(CUSTFL146)
     C     'deleted'     DSPLY
     C                   ENDIF
      /free
  EXEC SQL DROP TABLE custfl146;
      /end-free
     C                   RETURN
