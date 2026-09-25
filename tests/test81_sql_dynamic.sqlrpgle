**FREE

// Test 81: Dynamic SQL — EXECUTE IMMEDIATE, PREPARE, EXECUTE

DCL-S connStr   VARCHAR(200);
DCL-S sqlStr    VARCHAR(256);
DCL-S empId     INT(10);
DCL-S empName   VARCHAR(50);
DCL-S empSal    PACKED(9:2);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test81.sqlite;';
// OpenRPG connects by ODBC connection string; an IBM i job is already connected.
/IF DEFINED(*OPENRPG)
EXEC SQL CONNECT USING :connStr;
/ENDIF

// EXECUTE IMMEDIATE
sqlStr = 'CREATE TABLE dyn81 (id INTEGER, name VARCHAR(50), salary DECIMAL(9,2))';
EXEC SQL EXECUTE IMMEDIATE :sqlStr;

// PREPARE + EXECUTE
sqlStr = 'INSERT INTO dyn81 (id, name, salary) VALUES(?, ?, ?)';
EXEC SQL PREPARE INS1 FROM :sqlStr;

empId = 1;
empName = 'Alice';
empSal = 75000.00;
EXEC SQL EXECUTE INS1 USING :empId, :empName, :empSal;

empId = 2;
empName = 'Bob';
empSal = 65000.00;
EXEC SQL EXECUTE INS1 USING :empId, :empName, :empSal;

// Verify with SELECT INTO
empId = 1;
EXEC SQL SELECT name, salary INTO :empName, :empSal
  FROM dyn81 WHERE id = :empId;
DSPLY empName;
DSPLY %CHAR(empSal);

empId = 2;
EXEC SQL SELECT name, salary INTO :empName, :empSal
  FROM dyn81 WHERE id = :empId;
DSPLY empName;
DSPLY %CHAR(empSal);

// Cleanup
sqlStr = 'DROP TABLE dyn81';
EXEC SQL EXECUTE IMMEDIATE :sqlStr;
/IF DEFINED(*OPENRPG)
EXEC SQL DISCONNECT;
/ENDIF

*INLR = *ON;
RETURN;
