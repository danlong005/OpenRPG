**FREE

// Test 77: Embedded SQL basics — INSERT, UPDATE, DELETE, SELECT INTO

DCL-S connStr   VARCHAR(200);
DCL-S name      VARCHAR(50);
DCL-S age       INT(10);
DCL-S salary    PACKED(9:2);
DCL-S empId     INT(10);
DCL-S count     INT(10);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test77.sqlite;';
// OpenRPG connects by ODBC connection string; an IBM i job is already connected.
/IF DEFINED(*OPENRPG)
EXEC SQL CONNECT USING :connStr;
/ENDIF

EXEC SQL CREATE TABLE emp77 (
  id INTEGER PRIMARY KEY,
  name VARCHAR(50),
  age INTEGER,
  salary DECIMAL(9,2)
);

// INSERT
empId = 1;
name = 'Alice';
age = 30;
salary = 75000.00;
EXEC SQL INSERT INTO emp77 (id, name, age, salary)
  VALUES(:empId, :name, :age, :salary);

empId = 2;
name = 'Bob';
age = 25;
salary = 65000.00;
EXEC SQL INSERT INTO emp77 (id, name, age, salary)
  VALUES(:empId, :name, :age, :salary);

// UPDATE
salary = 80000.00;
empId = 1;
EXEC SQL UPDATE emp77 SET salary = :salary WHERE id = :empId;

// SELECT INTO
empId = 1;
EXEC SQL SELECT name, age, salary
  INTO :name, :age, :salary
  FROM emp77 WHERE id = :empId;

DSPLY name;
DSPLY %CHAR(age);
DSPLY %CHAR(salary);

// DELETE
empId = 2;
EXEC SQL DELETE FROM emp77 WHERE id = :empId;

// COUNT after delete
EXEC SQL SELECT COUNT(*) INTO :count FROM emp77;
DSPLY %CHAR(count);

EXEC SQL COMMIT;
EXEC SQL DROP TABLE emp77;
/IF DEFINED(*OPENRPG)
EXEC SQL DISCONNECT;
/ENDIF

*INLR = *ON;
