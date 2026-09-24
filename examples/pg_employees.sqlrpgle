**FREE

// Example: Query a PostgreSQL database from RPG
// Connects via ODBC, lists all Engineering employees, then reports
// the total payroll for that department.
//
// Prerequisites (macOS):
//   brew install psqlodbc
//   Register the driver — see README "Database Connectivity" section.
//
// Run:
//   rpgc pg_employees.sqlrpgle -o pg_employees
//   ./pg_employees

DCL-S connStr  VARCHAR(200);
DCL-S empName  VARCHAR(50);
DCL-S dept     VARCHAR(30);
DCL-S salary   PACKED(9:2);
DCL-S total    PACKED(11:2);
DCL-S rowCount INT(10);
DCL-S dspLine  VARCHAR(52);   // DSPLY shows at most 52 characters

// Connect — adjust Server/Uid to match your PostgreSQL setup
connStr = 'Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=rpgdemo;Uid=dlong;Pwd=;';
EXEC SQL CONNECT USING :connStr;

// Count Engineering employees
EXEC SQL SELECT COUNT(*), SUM(salary)
         INTO   :rowCount, :total
         FROM   employees
         WHERE  dept = 'Engineering';

DSPLY ('Engineering headcount: ' + %CHAR(rowCount));
DSPLY ('Total payroll:         $' + %CHAR(total));
DSPLY '---';

// Cursor over Engineering employees ordered by salary descending
EXEC SQL DECLARE c1 CURSOR FOR
  SELECT name, salary
  FROM   employees
  WHERE  dept = 'Engineering'
  ORDER  BY salary DESC;

EXEC SQL OPEN c1;

DOW SQLCODE = 0;
  EXEC SQL FETCH c1 INTO :empName, :salary;
  IF SQLCODE = 0;
    dspLine = empName + '  $' + %CHAR(salary);
    DSPLY dspLine;
  ENDIF;
ENDDO;

EXEC SQL CLOSE c1;
EXEC SQL DISCONNECT;

*INLR = *ON;
