**FREE

// Test 84: SQL Connection — CONNECT USING, DISCONNECT, CONNECT RESET

DCL-S connStr   VARCHAR(256);
DCL-S empName   VARCHAR(50);
DCL-S empId     INT(10);
DCL-S count     INT(10);

// Connect using connection string
connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test84.sqlite;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE emp84 (id INTEGER, name VARCHAR(50));
EXEC SQL INSERT INTO emp84 VALUES(1, 'Alice');
EXEC SQL INSERT INTO emp84 VALUES(2, 'Bob');

empId = 1;
EXEC SQL SELECT name INTO :empName FROM emp84 WHERE id = :empId;
DSPLY empName;

// Disconnect
EXEC SQL DISCONNECT;

// Reconnect
EXEC SQL CONNECT USING :connStr;

EXEC SQL SELECT COUNT(*) INTO :count FROM emp84;
DSPLY ('Count=' + %CHAR(count));

// CONNECT RESET
EXEC SQL DROP TABLE emp84;
EXEC SQL CONNECT RESET;

DSPLY 'Connection test passed';

*INLR = *ON;
RETURN;
