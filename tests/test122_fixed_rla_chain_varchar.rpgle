     HDFTACTGRP(*NO)
     FCUSTFL122 IF   E             DISK    KEYED
     F                                     EXTDESC('CUSTFL122')
     Dkey              S             10A   VARYING
      /free
       EXEC SQL CREATE TABLE custfl122 (
         CUSTNO VARCHAR(10) PRIMARY KEY,
         CUSTNAME VARCHAR(50)
       );
       EXEC SQL INSERT INTO custfl122 VALUES('C001','Alice');
       EXEC SQL INSERT INTO custfl122 VALUES('C002','Bob');
       key = 'C002';
       CHAIN key CUSTFL122;
       IF %FOUND(CUSTFL122);
         DSPLY CUSTNO;
         DSPLY CUSTNAME;
       ENDIF;
       key = 'Z999';
       CHAIN key CUSTFL122;
       IF NOT %FOUND(CUSTFL122);
         DSPLY 'not found';
       ENDIF;
       EXEC SQL DROP TABLE custfl122;
       *INLR = *ON;
      /end-free
