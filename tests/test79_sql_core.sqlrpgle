**FREE

// Test 79: Core SQL with SQLCODE/SQLSTATE diagnostics

DCL-S connStr   VARCHAR(200);
DCL-S empName   VARCHAR(50);
DCL-S empAge    INT(10);
DCL-S empSal    PACKED(9:2);
DCL-S empId     INT(10);
DCL-S empCount  INT(10);
DCL-S sqlStatus INT(10);
DCL-S sqlSt     CHAR(5);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test79.sqlite;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE emp79 (
  id INTEGER PRIMARY KEY,
  name VARCHAR(50),
  age INTEGER,
  salary DECIMAL(9,2)
);

// Insert rows and check SQLCODE
empId = 1;
empName = 'Alice';
empAge = 30;
empSal = 75000.00;
EXEC SQL INSERT INTO emp79 (id, name, age, salary)
  VALUES(:empId, :empName, :empAge, :empSal);
sqlStatus = SQLCOD;
DSPLY ('Insert SQLCODE=' + %CHAR(sqlStatus));

empId = 2;
empName = 'Bob';
empAge = 25;
empSal = 65000.00;
EXEC SQL INSERT INTO emp79 (id, name, age, salary)
  VALUES(:empId, :empName, :empAge, :empSal);

// Update
empSal = 80000.00;
empId = 1;
EXEC SQL UPDATE emp79 SET salary = :empSal WHERE id = :empId;

// Delete
empId = 2;
EXEC SQL DELETE FROM emp79 WHERE id = :empId;

// SELECT INTO
empId = 1;
EXEC SQL SELECT name, age, salary
  INTO :empName, :empAge, :empSal
  FROM emp79 WHERE id = :empId;
sqlSt = SQLSTT;
DSPLY ('Select SQLSTATE=' + sqlSt);

DSPLY empName;
DSPLY %CHAR(empAge);
DSPLY %CHAR(empSal);

// Count
EXEC SQL SELECT COUNT(*) INTO :empCount FROM emp79;
DSPLY %CHAR(empCount);

// Not found
empId = 999;
EXEC SQL SELECT name INTO :empName FROM emp79 WHERE id = :empId;
sqlStatus = SQLCOD;
DSPLY ('NotFound SQLCODE=' + %CHAR(sqlStatus));

EXEC SQL COMMIT;
EXEC SQL ROLLBACK;
EXEC SQL DROP TABLE emp79;
EXEC SQL DISCONNECT;

*INLR = *ON;
