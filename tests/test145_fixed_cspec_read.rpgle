     HDFTACTGRP(*NO)
     FCUSTFL145 I    E             DISK
     F                                     EXTDESC('custfl145')
      /free
  EXEC SQL CREATE TABLE custfl145 (
    CUSTNO VARCHAR(10),
    CUSTNAME VARCHAR(50)
  );
  EXEC SQL INSERT INTO custfl145 VALUES('A001','Alice');
  EXEC SQL INSERT INTO custfl145 VALUES('A002','Bob');
      /end-free
     C                   READ      CUSTFL145
     C                   DOW       NOT %EOF(CUSTFL145)
     C     CUSTNAME      DSPLY
     C                   READ      CUSTFL145
     C                   ENDDO
      /free
  EXEC SQL DROP TABLE custfl145;
      /end-free
     C                   RETURN
