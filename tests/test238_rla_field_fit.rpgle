**FREE
// Externally described fields hold their column's declared shape.
//
// Record-level reads copied each column value into its field exactly as
// the driver returned it, and the fields were unsized strings, so a CHAR(6)
// key column read back as 'K1' was two bytes long, and the field was empty
// before any read. On IBM i a CHAR column is a fixed-length field: 'K1'
// plus four blanks, and six blanks to start with. A VARCHAR column is a
// varying field and is not padded; a DECIMAL column has its scale.
// tests/CUSTFL238.extdesc records which is which (the trailing kind).
DCL-F CUSTFL238 DISK KEYED EXTDESC('CUSTFL238');

DCL-S connStr VARCHAR(200);
DCL-S key     CHAR(6);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test238.sqlite;';
EXEC SQL CONNECT USING :connStr;
EXEC SQL DROP TABLE IF EXISTS custfl238;
EXEC SQL CREATE TABLE custfl238 (
  CUSTNO   CHAR(6) PRIMARY KEY,
  CUSTNAME VARCHAR(20),
  CUSTBAL  DECIMAL(7,2),
  RATE     REAL
);
EXEC SQL INSERT INTO custfl238 VALUES('K1','Short',12.5,0.125);

// Before any read the fixed-length field is blanks, the varying one empty.
DSPLY ('RESULT:INITNO=[' + CUSTNO + ']');
DSPLY ('RESULT:INITNAME=[' + CUSTNAME + ']');

key = 'K1';
CHAIN key CUSTFL238;
IF %FOUND(CUSTFL238);
  DSPLY ('RESULT:CUSTNO=[' + CUSTNO + '] ' + %CHAR(%LEN(CUSTNO)));
  DSPLY ('RESULT:CUSTNAME=[' + CUSTNAME + ']');
  DSPLY ('RESULT:CUSTBAL=' + %CHAR(CUSTBAL));
  DSPLY ('RESULT:RATE=' + %CHAR(RATE));
ENDIF;

// Assignment into a file field fits it too, and the padded key still
// finds its row on a database that compares without padding.
CUSTNO = 'K2';
CUSTNAME = 'A NAME LONGER THAN TWENTY';
CUSTBAL = 3.456;
RATE = 1.5;
WRITE CUSTFL238;
key = 'K2';
CHAIN key CUSTFL238;
IF %FOUND(CUSTFL238);
  DSPLY ('RESULT:WROTE=[' + CUSTNO + '][' + CUSTNAME + '] ' + %CHAR(CUSTBAL));
ENDIF;

EXEC SQL DROP TABLE custfl238;
EXEC SQL DISCONNECT;
*INLR = *ON;
