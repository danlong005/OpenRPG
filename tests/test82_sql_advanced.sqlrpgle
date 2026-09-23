**FREE

// Test 82: Advanced SQL — GET DIAGNOSTICS, SAVEPOINT

DCL-S connStr   VARCHAR(200);
DCL-S empId     INT(10);
DCL-S empName   VARCHAR(50);
DCL-S empSal    PACKED(9:2);
DCL-S rowCount  INT(10);
DCL-S empCount  INT(10);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test82.sqlite;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE adv82 (
  id INTEGER PRIMARY KEY,
  name VARCHAR(50),
  salary DECIMAL(9,2)
);

empId = 1;
empName = 'Alice';
empSal = 75000.00;
EXEC SQL INSERT INTO adv82 (id, name, salary)
  VALUES(:empId, :empName, :empSal);

empId = 2;
empName = 'Bob';
empSal = 65000.00;
EXEC SQL INSERT INTO adv82 (id, name, salary)
  VALUES(:empId, :empName, :empSal);

empId = 3;
empName = 'Charlie';
empSal = 90000.00;
EXEC SQL INSERT INTO adv82 (id, name, salary)
  VALUES(:empId, :empName, :empSal);

// GET DIAGNOSTICS ROW_COUNT after UPDATE
EXEC SQL UPDATE adv82 SET salary = salary + 1000 WHERE salary < 80000;
EXEC SQL GET DIAGNOSTICS :rowCount = ROW_COUNT;
DSPLY ('Updated rows=' + %CHAR(rowCount));

// SAVEPOINT
EXEC SQL SAVEPOINT sp1;

EXEC SQL DELETE FROM adv82 WHERE id = 3;
EXEC SQL GET DIAGNOSTICS :rowCount = ROW_COUNT;
DSPLY ('Deleted rows=' + %CHAR(rowCount));

// ROLLBACK TO SAVEPOINT — should restore id=3
EXEC SQL ROLLBACK TO SAVEPOINT sp1;

// Verify id=3 is back
EXEC SQL SELECT COUNT(*) INTO :empCount FROM adv82;
DSPLY ('After rollback count=' + %CHAR(empCount));

EXEC SQL COMMIT;
EXEC SQL DROP TABLE adv82;
EXEC SQL DISCONNECT;

*INLR = *ON;
RETURN;
