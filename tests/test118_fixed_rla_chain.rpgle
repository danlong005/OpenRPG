     HDFTACTGRP(*NO)
     FCUSTFL118 I    E             DISK    KEYED
     F                                     EXTDESC('custfl118')
     DcustomerNumb...  S
     Der               S             10I 0
      /free
  EXEC SQL CREATE TABLE custfl118 (
    CUSTNO INTEGER PRIMARY KEY,
    CUSTNAME VARCHAR(50)
  );
  EXEC SQL INSERT INTO custfl118 VALUES(1,'Alpha');
  EXEC SQL INSERT INTO custfl118 VALUES(2,'Beta');
  EXEC SQL INSERT INTO custfl118 VALUES(3,'Gamma');
  customerNumber = 2;
  CHAIN customerNumber CUSTFL118;
  IF %FOUND(CUSTFL118);
    DSPLY CUSTNO;
    DSPLY CUSTNAME;
  ENDIF;
  customerNumber = 999;
  CHAIN customerNumber CUSTFL118;
  IF NOT %FOUND(CUSTFL118);
    DSPLY 'not found';
  ENDIF;
  EXEC SQL DROP TABLE custfl118;
  *INLR = *ON;
      /end-free
