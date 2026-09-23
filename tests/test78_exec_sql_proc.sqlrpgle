**FREE

// Test 78: Embedded SQL in procedures

DCL-S connStr VARCHAR(200);
DCL-S result  VARCHAR(100);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test78.sqlite;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE emp78 (
  id INTEGER PRIMARY KEY,
  name VARCHAR(50),
  salary DECIMAL(9,2)
);

EXEC SQL INSERT INTO emp78 VALUES(1, 'Alice', 75000.00);
EXEC SQL INSERT INTO emp78 VALUES(2, 'Bob', 65000.00);

result = GetEmployeeName(1);
dspLine = result;
DSPLY dspLine;

UpdateSalary(2 : 5000.00);

result = GetEmployeeName(2);
dspLine = result;
DSPLY dspLine;

EXEC SQL DROP TABLE emp78;
EXEC SQL DISCONNECT;

*INLR = *ON;

DCL-PROC GetEmployeeName;
  DCL-PI VARCHAR(100);
    empId INT(10) VALUE;
  END-PI;

  DCL-S empName VARCHAR(100);

  EXEC SQL SELECT name INTO :empName FROM emp78 WHERE id = :empId;

  RETURN empName;
END-PROC;

DCL-PROC UpdateSalary;
  DCL-PI;
    empId  INT(10) VALUE;
    amount PACKED(9:2) VALUE;
  END-PI;

  EXEC SQL UPDATE emp78 SET salary = salary + :amount WHERE id = :empId;
  EXEC SQL COMMIT;

END-PROC;
