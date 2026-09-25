**FREE

// Test 83: Multi-row FETCH and INSERT

DCL-S connStr   VARCHAR(200);
DCL-S ids       INT(10) DIM(10);
DCL-S names     VARCHAR(50) DIM(10);
DCL-S salaries  PACKED(9:2) DIM(10);
DCL-S nRows     INT(10);
DCL-S i         INT(10);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test83.sqlite;';
// OpenRPG connects by ODBC connection string; an IBM i job is already connected.
/IF DEFINED(*OPENRPG)
EXEC SQL CONNECT USING :connStr;
/ENDIF

EXEC SQL CREATE TABLE mr83 (
  id INTEGER,
  name VARCHAR(50),
  salary DECIMAL(9,2)
);

// Set up arrays
ids(1) = 1;
names(1) = 'Alice';
salaries(1) = 75000.00;
ids(2) = 2;
names(2) = 'Bob';
salaries(2) = 65000.00;
ids(3) = 3;
names(3) = 'Charlie';
salaries(3) = 90000.00;

// Multi-row INSERT
nRows = 3;
EXEC SQL INSERT INTO mr83 (id, name, salary)
  VALUES(:ids, :names, :salaries)
  FOR :nRows ROWS;

// Read back with cursor + multi-row FETCH
EXEC SQL DECLARE mrCur CURSOR FOR
  SELECT id, name, salary FROM mr83 ORDER BY id;

EXEC SQL OPEN mrCur;

// Clear arrays before fetch
FOR i = 1 TO 10;
  ids(i) = 0;
  names(i) = '';
  salaries(i) = 0;
ENDFOR;

nRows = 10;
EXEC SQL FETCH mrCur FOR :nRows ROWS
  INTO :ids, :names, :salaries;

EXEC SQL CLOSE mrCur;

// Display fetched results
FOR i = 1 TO 3;
  dspLine = (%CHAR(ids(i)) + ' ' + names(i) + ' ' + %CHAR(salaries(i)));
  DSPLY dspLine;
ENDFOR;

EXEC SQL DROP TABLE mr83;
/IF DEFINED(*OPENRPG)
EXEC SQL DISCONNECT;
/ENDIF

*INLR = *ON;
RETURN;
