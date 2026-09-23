**FREE

// Test 80: SQL Cursor Operations — DECLARE, OPEN, FETCH, CLOSE

DCL-S connStr   VARCHAR(200);
DCL-S empName   VARCHAR(50);
DCL-S empAge    INT(10);
DCL-S empSal    PACKED(9:2);
DCL-S empId     INT(10);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test80.sqlite;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE emp80 (
  id INTEGER PRIMARY KEY,
  name VARCHAR(50),
  age INTEGER,
  salary DECIMAL(9,2)
);

empId = 1;
empName = 'Alice';
empAge = 30;
empSal = 75000.00;
EXEC SQL INSERT INTO emp80 (id, name, age, salary)
  VALUES(:empId, :empName, :empAge, :empSal);

empId = 2;
empName = 'Bob';
empAge = 25;
empSal = 65000.00;
EXEC SQL INSERT INTO emp80 (id, name, age, salary)
  VALUES(:empId, :empName, :empAge, :empSal);

empId = 3;
empName = 'Charlie';
empAge = 35;
empSal = 90000.00;
EXEC SQL INSERT INTO emp80 (id, name, age, salary)
  VALUES(:empId, :empName, :empAge, :empSal);

// Cursor for all employees
EXEC SQL DECLARE empCur CURSOR FOR
  SELECT name, age, salary FROM emp80 ORDER BY id;

EXEC SQL OPEN empCur;

EXEC SQL FETCH empCur INTO :empName, :empAge, :empSal;
DOW SQLCOD = 0;
  dspLine = (empName + ' age=' + %CHAR(empAge));
  DSPLY dspLine;
  EXEC SQL FETCH empCur INTO :empName, :empAge, :empSal;
ENDDO;

EXEC SQL CLOSE empCur;

// Cursor with host variable in WHERE
EXEC SQL DECLARE salCur CURSOR FOR
  SELECT name, salary FROM emp80 WHERE salary > :empSal;

empSal = 70000.00;
EXEC SQL OPEN salCur;

EXEC SQL FETCH salCur INTO :empName, :empSal;
DOW SQLCOD = 0;
  dspLine = (empName + ' sal=' + %CHAR(empSal));
  DSPLY dspLine;
  EXEC SQL FETCH salCur INTO :empName, :empSal;
ENDDO;

EXEC SQL CLOSE salCur;

EXEC SQL DROP TABLE emp80;
EXEC SQL DISCONNECT;

*INLR = *ON;
RETURN;
