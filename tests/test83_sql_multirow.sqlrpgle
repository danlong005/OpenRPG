**FREE

// Test 83: Multi-row FETCH and INSERT

DCL-S connStr   VARCHAR(200);
// Db2 for i moves multiple rows through a host structure array: one DS
// array, one subfield per column.
DCL-DS emp QUALIFIED DIM(10);
  id     INT(10);
  name   VARCHAR(50);
  salary PACKED(9:2);
END-DS;
DCL-S nRows     INT(10);
DCL-S i         INT(10);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

/IF DEFINED(*OPENRPG)
// OpenRPG also accepts one array per column with FOR :n ROWS (the Db2 LUW
// spelling), which IBM i rejects.
DCL-S ids       INT(10) DIM(10);
DCL-S names     VARCHAR(50) DIM(10);
DCL-S salaries  PACKED(9:2) DIM(10);
/ENDIF

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

// Set up the rows
emp(1).id = 1;
emp(1).name = 'Alice';
emp(1).salary = 75000.00;
emp(2).id = 2;
emp(2).name = 'Bob';
emp(2).salary = 65000.00;
emp(3).id = 3;
emp(3).name = 'Charlie';
emp(3).salary = 90000.00;

// Multi-row (blocked) INSERT
nRows = 3;
EXEC SQL INSERT INTO mr83 (id, name, salary)
  :nRows ROWS VALUES(:emp);

// Read back with cursor + multi-row FETCH
EXEC SQL DECLARE mrCur CURSOR FOR
  SELECT id, name, salary FROM mr83 ORDER BY id;

EXEC SQL OPEN mrCur;

FOR i = 1 TO 10;
  emp(i).id = 0;
  emp(i).name = '';
  emp(i).salary = 0;
ENDFOR;

nRows = 10;
EXEC SQL FETCH mrCur FOR :nRows ROWS INTO :emp;

EXEC SQL CLOSE mrCur;

// Display fetched results
FOR i = 1 TO 3;
  dspLine = (%CHAR(emp(i).id) + ' ' + emp(i).name + ' ' + %CHAR(emp(i).salary));
  DSPLY dspLine;
ENDFOR;

/IF DEFINED(*OPENRPG)
// The same round trip through one array per column
EXEC SQL DELETE FROM mr83;

ids(1) = 4;
names(1) = 'Dana';
salaries(1) = 55000.00;
ids(2) = 5;
names(2) = 'Eve';
salaries(2) = 80000.00;

nRows = 2;
EXEC SQL INSERT INTO mr83 (id, name, salary)
  VALUES(:ids, :names, :salaries)
  FOR :nRows ROWS;

EXEC SQL DECLARE mrCur2 CURSOR FOR
  SELECT id, name, salary FROM mr83 ORDER BY id;

EXEC SQL OPEN mrCur2;

FOR i = 1 TO 10;
  ids(i) = 0;
  names(i) = '';
  salaries(i) = 0;
ENDFOR;

nRows = 10;
EXEC SQL FETCH mrCur2 FOR :nRows ROWS
  INTO :ids, :names, :salaries;

EXEC SQL CLOSE mrCur2;

FOR i = 1 TO 2;
  dspLine = (%CHAR(ids(i)) + ' ' + names(i) + ' ' + %CHAR(salaries(i)));
  DSPLY dspLine;
ENDFOR;
/ENDIF

EXEC SQL DROP TABLE mr83;
/IF DEFINED(*OPENRPG)
EXEC SQL DISCONNECT;
/ENDIF

*INLR = *ON;
RETURN;
